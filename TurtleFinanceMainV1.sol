// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./TurtleFinancePairV1.sol";
import "./interfaces/ITurtleFinanceTokenPoolBank.sol";
import "./interfaces/IUniswapRouterV2.sol";

contract TurtleFinanceMainV1 is Ownable {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct TokenPool {
        address addr;
        uint256 totalQuantity;
        uint256 mainBalance;
        address bankAddr;
        uint256 bankTotalSaveQuantity;
        uint256 bankTotalTakeQuantity;
        uint256 bankBalance;
        uint256 minHoldRate;
        uint256 expHoldRate;
        uint256 maxHoldRate;
    }

    struct UniswapRouterV2SwapTokenParams {
        uint256 amountIn;
        uint256 amountOutMin;
        address[] path;
        uint256 deadline;
    }

    mapping(address => TokenPool) tokenPoolMap;
    mapping(address => uint256) pairsSwapItemIdSEQMap;

    EnumerableSet.AddressSet pairs;
    EnumerableSet.AddressSet tokenPools;
    address public mdexSwapMiningAddr;
    address public treTokenAddr;
    address public uniswapRouterV2Addr;
    address payable public platformFeeReceiver;
    address private _operator;

    bool public lockOperator;

    event Action(address indexed pair, string act, address indexed maker, uint256 indexed itemId, uint16 holdIdx, uint256 token0quantity, uint256 token1quantity);

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);

    event SetTokenPool(address indexed token, address bank, uint256 minHoldRate, uint256 expHoldRate, uint256 maxHoldRate);

    event TokenBankTake(address indexed token, address bank, uint256 quantity);
    event TokenBankSave(address indexed token, address bank, uint256 quantity);

    event AddPair(address indexed pair);

    constructor(address treTokenAddr_, address uniswapRouterV2Addr_, address mdexSwapMiningAddr_){
        require(treTokenAddr_ != address(0), "treTokenAddr_ address cannot be 0");
        require(uniswapRouterV2Addr_ != address(0), "uniswapRouterV2Addr_ address cannot be 0");
        _operator = _msgSender();
        platformFeeReceiver = payable(msg.sender);
        treTokenAddr = treTokenAddr_;
        uniswapRouterV2Addr = uniswapRouterV2Addr_;
        mdexSwapMiningAddr = mdexSwapMiningAddr_;
    }

    function _transferOperator(address newOperator_) internal {
        require(
            newOperator_ != address(0),
            'operator: zero address given for new operator'
        );
        emit OperatorTransferred(_operator, newOperator_);
        _operator = newOperator_;
    }

    function _autoCreateTokenPool(address token) private {
        if (!tokenPools.contains(token)) {
            TokenPool memory pool;
            pool.addr = token;
            tokenPoolMap[token] = pool;
            tokenPools.add(token);
        }
    }

    function _tokenBankSave(address token, uint256 quantity) private {
        TokenPool storage pool = tokenPoolMap[token];
        ITurtleFinanceTokenPoolBank bank = ITurtleFinanceTokenPoolBank(pool.bankAddr);
        IERC20 et = IERC20(token);
        et.safeTransfer(address(bank), quantity);
        bank.save(token, quantity);
        pool.bankTotalSaveQuantity += quantity;
        pool.bankBalance = bank.balanceOf(token);
        pool.mainBalance = et.balanceOf(address(this));
        emit TokenBankSave(token, address(bank), quantity);
    }

    function _tokenBankTake(address token, uint256 quantity) private {
        TokenPool storage pool = tokenPoolMap[token];
        ITurtleFinanceTokenPoolBank bank = ITurtleFinanceTokenPoolBank(pool.bankAddr);
        IERC20 et = IERC20(token);
        uint256 balance = et.balanceOf(address(this));
        bank.take(token, quantity);
        require(et.balanceOf(address(this)) - balance == quantity, "bank take fail.");
        pool.bankTotalTakeQuantity += quantity;
        pool.bankBalance = bank.balanceOf(token);
        pool.mainBalance = et.balanceOf(address(this));
        emit TokenBankTake(token, address(bank), quantity);
    }

    function _tokenPoolBalanceChange(address token) private {
        TokenPool storage pool = tokenPoolMap[token];
        IERC20 et = IERC20(token);
        if (pool.bankAddr == address(0)) {
            pool.bankBalance = 0;
            pool.mainBalance = et.balanceOf(address(this));
            return;
        }
        uint256 minHold = pool.totalQuantity * pool.minHoldRate / 1E4;
        uint256 expHold = pool.totalQuantity * pool.expHoldRate / 1E4;
        uint256 maxHold = pool.totalQuantity * pool.maxHoldRate / 1E4;
        if (pool.mainBalance <= minHold) {
            uint256 quantity = expHold - pool.mainBalance;
            if (quantity > 0) {
                _tokenBankTake(token, quantity);
            }
        } else if (pool.mainBalance >= maxHold) {
            uint256 quantity = pool.mainBalance - expHold;
            if (quantity > 0) {
                _tokenBankSave(token, quantity);
            }
        }
    }

    function _tokenPoolTransfer(address toAddr, address token, uint256 quantity) private {
        TokenPool storage pool = tokenPoolMap[token];
        pool.totalQuantity = pool.totalQuantity - quantity;
        IERC20 et = IERC20(token);
        if (pool.bankAddr != address(0)) {
            uint256 needTake = 0;
            if (quantity > pool.mainBalance)
                needTake = quantity - pool.mainBalance;
            if (needTake > 0) {
                _tokenBankTake(token, needTake);
            }
        }
        et.safeTransfer(toAddr, quantity);
        pool.mainBalance = et.balanceOf(address(this));
        _tokenPoolBalanceChange(token);
    }

    function _tokenPoolReceived(address token, uint256 quantity) private {
        TokenPool storage pool = tokenPoolMap[token];
        pool.totalQuantity = pool.totalQuantity + quantity;
        pool.mainBalance = IERC20(token).balanceOf(address(this));
        _tokenPoolBalanceChange(token);
    }

    function _getUniswapSwapFunctionData(UniswapRouterV2SwapTokenParams memory params, address to) private view returns (bytes memory){
        return abi.encodeWithSelector(
            bytes4(keccak256("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)")), // 0x38ED1739
            params.amountIn,
            params.amountOutMin,
            params.path,
            address(this),
            params.deadline
        );
    }

    modifier onlyNotLocked(){
        require(!lockOperator, 'operator: locked');
        _;
    }

    modifier onlyOperator() {
        require(!lockOperator, 'operator: locked');
        require(
            _operator == msg.sender || owner() == msg.sender,
            'operator: caller is not the operator'
        );
        _;
    }

    // --------------- view functions -----------------------


    function operator() external view returns (address) {
        return _operator;
    }

    function getPairs() external view returns (TurtleFinancePairV1.PairInfo[] memory){
        uint256 len = pairs.length();
        TurtleFinancePairV1.PairInfo[] memory infos = new TurtleFinancePairV1.PairInfo[](len);
        for (uint256 i = 0; i < len; i++) {
            address pairAddr = pairs.at(i);
            TurtleFinancePairV1.PairInfo memory pi = TurtleFinancePairV1(pairAddr).pairInfo();
            infos[i] = pi;
        }
        return infos;
    }

    function getTokenPools() external view returns (TokenPool[] memory){
        uint256 len = tokenPools.length();
        TokenPool[] memory pools = new TokenPool[](len);
        for (uint256 i = 0; i < len; i++) {
            pools[i] = tokenPoolMap[tokenPools.at(i)];
        }
        return pools;
    }

    function pairMdexSwapMiningGetUserReward(address pairAddr, uint256 pid) external view returns (uint256, uint256){
        require(pairs.contains(pairAddr), "pair not exists");
        require(mdexSwapMiningAddr != address(0), "Not support");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddr);
        return pair.mdexSwapMiningGetUserReward(mdexSwapMiningAddr, pid);
    }

    // --------------- view functions end -----------------------




    // --------------- admin functions -----------------------

    function transferOperator(address newOperator_) external onlyOwner {
        _transferOperator(newOperator_);
    }

    function setPlatformFeeReceiver(address payable platformFeeReceiver_) external onlyOwner {
        require(platformFeeReceiver_ != address(0), "platformFeeReceiver_ address cannot be 0");
        platformFeeReceiver = platformFeeReceiver_;
    }

    function pairMdexSwapMiningTakerWithdraw(address pairAddr, address to) external onlyOwner {
        require(pairs.contains(pairAddr), "pair not exists");
        require(mdexSwapMiningAddr != address(0), "Not support");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddr);
        pair.mdexSwapMiningTakerWithdraw(mdexSwapMiningAddr, to);
    }

    function tokenPoolSet(address addr, address bankAddr, uint256 min, uint256 exp, uint256 max) external onlyOwner {
        TokenPool storage pool = tokenPoolMap[addr];
        require(pool.addr == addr && addr != address(0), "token not exists.");
        require(min > 0 && min <= exp && exp <= max && max < 1E4, "rate error");
        pool.minHoldRate = min;
        pool.expHoldRate = exp;
        pool.maxHoldRate = max;
        if (pool.bankAddr != address(0) && pool.bankAddr != bankAddr) {
            if (pool.bankBalance > 0)
                _tokenBankTake(pool.addr, pool.bankBalance);
            ITurtleFinanceTokenPoolBank(pool.bankAddr).destroy(pool.addr);
            pool.bankTotalTakeQuantity = 0;
            pool.bankTotalSaveQuantity = 0;
            if (bankAddr != address(0)) {
                ITurtleFinanceTokenPoolBank newBank = ITurtleFinanceTokenPoolBank(bankAddr);
                require(newBank.mainContractAddress() == address(this), "Bank main contract not this");
                newBank.create(pool.addr);
            }
        }
        pool.bankAddr = bankAddr;
        _tokenPoolBalanceChange(pool.addr);
        emit SetTokenPool(pool.addr, bankAddr, min, exp, max);
    }


    function setLockOperator(bool is_lock) external onlyOwner {
        lockOperator = is_lock;
    }

    function withdrawToken(address token, address payable to, uint256 quantity) external onlyOwner {
        if (token == address(0))
            to.transfer(quantity);
        else
            IERC20(token).safeTransfer(to, quantity);
    }

    function addPair(address pairAddress, address uniswapRouterV2Addr_) external onlyOwner {
        require(!pairs.contains(pairAddress), "repeat add");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        require(address(pair.mainContract()) == address(this), "Main address error.");
        if (uniswapRouterV2Addr_ != address(0))
            pair.setUniswapRouterV2Addr(uniswapRouterV2Addr_);
        else
            pair.setUniswapRouterV2Addr(uniswapRouterV2Addr);
        TurtleFinancePairV1.PairInfo memory info = pair.pairInfo();
        _autoCreateTokenPool(info.token0);
        _autoCreateTokenPool(info.token1);
        pairs.add(pairAddress);
        pairsSwapItemIdSEQMap[pairAddress] = pairs.length() * 1E10;
        emit AddPair(pairAddress);
    }

    function pairAddRewardPool(address pairAddress, uint256 totalRewardQuantity, uint256 startTime, uint256 periodTime) onlyOwner external {
        require(pairs.contains(pairAddress), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        pair.rewardAddPool(msg.sender, totalRewardQuantity, startTime, periodTime);
    }

    // --------------- admin functions end -----------------------





    // --------------- to pair functions -----------------------
    function pairSetInfo(address pairAddress, TurtleFinancePairV1.PairInfo calldata form) onlyOperator external {
        require(pairs.contains(pairAddress), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        pair.setPairInfo(form);
    }

    function pairSwap(address pairAddress, uint256 itemId, UniswapRouterV2SwapTokenParams memory swapParams) onlyOperator external {
        require(pairs.contains(pairAddress), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        TurtleFinancePairV1.PairInfo memory info = pair.pairInfo();
        TurtleFinancePairV1.SwapItem memory item = pair.getSwapInfo(itemId);
        require(item.enabled, "SwapItem disabled");
        if (item.holdIdx == 0) {
            uint pathLen = swapParams.path.length;
            require(swapParams.amountIn == item.token0Balance, "swap in amount error");
            require(swapParams.path[0] == info.token0, "swap from token error");
            require(swapParams.path[pathLen - 1] == info.token1, "swap to token error");
            _tokenPoolTransfer(pairAddress, info.token0, item.token0Balance);
        } else {
            uint pathLen = swapParams.path.length;
            require(swapParams.amountIn == item.token1Balance, "swap in amount error");
            require(swapParams.path[0] == info.token1, "swap from token error");
            require(swapParams.path[pathLen - 1] == info.token0, "swap to token error");
            _tokenPoolTransfer(pairAddress, info.token1, item.token1Balance);
        }
        uint256 platformFee = 0;

        bytes memory marketData = _getUniswapSwapFunctionData(swapParams, pairAddress);

        (item, platformFee) = pair.swap(itemId, marketData);

        if (item.holdIdx == 0) {
            if (platformFee > 0) {
                IERC20 et = IERC20(info.token0);
                et.safeTransfer(platformFeeReceiver, platformFee);
            }
            _tokenPoolReceived(info.token0, item.token0Balance);
        } else {
            if (platformFee > 0) {
                IERC20 et = IERC20(info.token1);
                et.safeTransfer(platformFeeReceiver, platformFee);
            }
            _tokenPoolReceived(info.token1, item.token1Balance);
        }
        emit Action(pairAddress, "swap", item.maker, item.id, item.holdIdx, item.token0Balance, item.token1Balance);
    }

    function pairCreate(address pairAddress, address maker, uint256 extId, uint16 holdIdx, uint256 token0Balance, uint256 token1Balance) onlyOperator external {
        require(pairs.contains(pairAddress), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        TurtleFinancePairV1.PairInfo memory info = pair.pairInfo();
        require(info.enabled, "Pair disabled");
        if (holdIdx == 0) {
            require(token0Balance >= info.minToken0, "0 too low");
            require(token0Balance <= info.maxToken0, "0 too high");
            IERC20 et = IERC20(info.token0);
            et.safeTransferFrom(maker, payable(address(this)), token0Balance);
            _tokenPoolReceived(info.token0, token0Balance);
        } else {
            require(token1Balance >= info.minToken1, "1 too low");
            require(token1Balance <= info.maxToken1, "1 too high");
            IERC20 et = IERC20(info.token1);
            et.safeTransferFrom(maker, payable(address(this)), token1Balance);
            _tokenPoolReceived(info.token1, token1Balance);
        }
        pairsSwapItemIdSEQMap[pairAddress] = pairsSwapItemIdSEQMap[pairAddress] + 1;
        uint256 itemId = pairsSwapItemIdSEQMap[pairAddress];
        TurtleFinancePairV1.SwapItem memory item = pair.create(maker, itemId, extId, holdIdx, token0Balance, token1Balance);
        emit Action(pairAddress, "create", item.maker, item.id, item.holdIdx, item.token0Balance, item.token1Balance);
    }

    function pairRemove(address pairAddress, uint256 itemId) onlyNotLocked external {
        require(pairs.contains(pairAddress), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddress);
        TurtleFinancePairV1.PairInfo memory info = pair.pairInfo();
        TurtleFinancePairV1.SwapItem memory item = pair.getSwapInfo(itemId);
        require(item.maker == msg.sender, "not maker");
        if (item.holdIdx == 0) {
            _tokenPoolTransfer(msg.sender, info.token0, item.token0Balance);
        } else {
            _tokenPoolTransfer(msg.sender, info.token1, item.token1Balance);
        }
        item = pair.remove(itemId);
        emit Action(pairAddress, "remove", item.maker, item.id, item.holdIdx, item.token0Balance, item.token1Balance);
    }

    function pairRewardEarned() external view returns (uint256){
        uint256 len = pairs.length();
        uint256 earned = 0;
        for (uint256 i = 0; i < len; i++) {
            address pairAddr = pairs.at(i);
            TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddr);
            uint256 e = pair.rewardEarned(msg.sender);
            earned = earned + e;
        }
        return earned;
    }

    function pairRewardGet() onlyNotLocked external {
        uint256 len = pairs.length();
        for (uint256 i = 0; i < len; i++) {
            address pairAddr = pairs.at(i);
            TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddr);
            pair.rewardGet(msg.sender);
        }
    }

    function pairRewardGetOfPair(address pairAddr) onlyNotLocked external {
        require(pairs.contains(pairAddr), "pair not exists");
        TurtleFinancePairV1 pair = TurtleFinancePairV1(pairAddr);
        pair.rewardGet(msg.sender);
    }

    // --------------- to pair functions end -----------------------

}
