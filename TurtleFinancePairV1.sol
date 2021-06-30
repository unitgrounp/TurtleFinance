// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./interfaces/ITurtleFinanceMainV1.sol";
import "./interfaces/IUniswapRouterV2.sol";
import "./interfaces/IMdexSwapMining.sol";
import "./TurtleFinanceTreRewardV1.sol";
import "./Utils.sol";

contract TurtleFinancePairV1 is Ownable {

    ITurtleFinanceMainV1 public mainContract;
    TurtleFinanceTreRewardV1 public reward;

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 private _firstItemId;
    uint256 private _lastItemId;

    struct PairInfo {
        bool enabled;
        address addr;
        address token0;
        address token1;
        uint256 minToken0;
        uint256 minToken1;
        uint256 maxToken0;
        uint256 maxToken1;
        uint platformFeeRate;
    }

    struct PairStats {
        uint256 totalCostToken0;
        uint256 totalCostToken1;
        uint256 totalRealToken0;
        uint256 totalRealToken1;
        uint256 totalFeeToken0;
        uint256 totalFeeToken1;
        uint256 totalItemCount;
        uint256 activeItemCount;
    }

    struct SwapItem {
        uint256 id;
        uint256 extId;
        bool enabled;
        address maker;
        uint16 costIdx;
        uint256 costToken0Quantity;
        uint256 costToken1Quantity;
        uint16 holdIdx;
        uint256 token0Balance;
        uint256 token1Balance;
    }

    address public uniswapRouterV2Addr;

    mapping(uint256 => SwapItem) private swapItemMap;
    mapping(uint256 => uint256) private swapItemExtMap;
    EnumerableSet.UintSet private swapItems;

    PairInfo private _pairInfo;
    PairStats private _pairStats;


    constructor (address main, address token0, address token1, uint256 rewardHalveTime, uint256 rewardHalveRate, uint256 rewardQuantity, uint256 rewardHalveMax)  {
        mainContract = ITurtleFinanceMainV1(main);
        _pairInfo.addr = address(this);
        _pairInfo.token0 = token0;
        _pairInfo.token1 = token1;
        transferOwnership(main);
        reward = new TurtleFinanceTreRewardV1(mainContract.treTokenAddr(), rewardHalveTime, rewardHalveRate, rewardQuantity, rewardHalveMax);
    }

    function getSwapItemIdRange() public view returns (uint256, uint256){
        return (_firstItemId, _lastItemId);
    }

    function getSwapInfo(uint256 itemId) public view returns (SwapItem memory){
        return swapItemMap[itemId];
    }

    function pairInfo() public view returns (PairInfo memory){
        return _pairInfo;
    }

    function pairStats() public view returns (PairStats memory){
        return _pairStats;
    }

    function mdexSwapMiningGetUserReward(address addr, uint256 pid) public view returns (uint256, uint256){
        return IMdexSwapMining(addr).getUserReward(pid);
    }

    function setUniswapRouterV2Addr(address uniswapRouterV2Addr_) public onlyOwner {
        uniswapRouterV2Addr = uniswapRouterV2Addr_;
    }

    function setPairInfo(PairInfo calldata form) public onlyOwner {
        _pairInfo.enabled = form.enabled;
        _pairInfo.minToken0 = form.minToken0;
        _pairInfo.minToken1 = form.minToken1;
        _pairInfo.maxToken0 = form.maxToken0;
        _pairInfo.maxToken1 = form.maxToken1;
        _pairInfo.platformFeeRate = form.platformFeeRate;
    }

    function mdexSwapMiningTakerWithdraw(address addr, address to) public onlyOwner {
        IMdexSwapMining c = IMdexSwapMining(addr);
        IERC20 mdx = IERC20(c.mdx());
        uint256 beforeMdxBalance = mdx.balanceOf(address(this));
        c.takerWithdraw();
        mdx.transfer(to, mdx.balanceOf(address(this)) - beforeMdxBalance);
    }

    function swap(uint256 itemId, bytes memory marketData) public onlyOwner returns (SwapItem memory, uint256){
        SwapItem storage item = swapItemMap[itemId];
        require(item.enabled, "disabled");
        IERC20 et0 = IERC20(_pairInfo.token0);
        IERC20 et1 = IERC20(_pairInfo.token1);
        int256 platformFee = 0;
        if (item.holdIdx == 0) {
            item.holdIdx = 1;
            _pairStats.totalRealToken0 -= item.token0Balance;
            require(item.token0Balance > 0, "balance overflow");
            et0.approve(uniswapRouterV2Addr, item.token0Balance);
            uint256 beforeTotal1Balance = et1.balanceOf(address(mainContract));
            Utils.functionCall(uniswapRouterV2Addr, marketData, string(abi.encodePacked("swap 0 to 1 fail-> ", "balance: ", Strings.toString(beforeTotal1Balance))));
            uint256 balance1Changed = et1.balanceOf(address(mainContract)) - beforeTotal1Balance;
            if (balance1Changed > item.token1Balance)
                platformFee = int256((balance1Changed - item.token1Balance) * uint256(_pairInfo.platformFeeRate) / 10000);
            if (platformFee < 0) platformFee = 0;
            item.token1Balance = balance1Changed - uint256(platformFee);
            _pairStats.totalRealToken1 += item.token1Balance;
            _pairStats.totalFeeToken1 += uint256(platformFee);
        } else {
            item.holdIdx = 0;
            _pairStats.totalRealToken1 -= item.token1Balance;
            require(item.token1Balance > 0, "balance overflow");
            et1.approve(uniswapRouterV2Addr, item.token1Balance);
            uint256 beforeTotal0Balance = et0.balanceOf(address(mainContract));
            Utils.functionCall(uniswapRouterV2Addr, marketData, string(abi.encodePacked("swap 1 to 0 fail-> ", "balance: ", Strings.toString(beforeTotal0Balance))));
            uint256 balance0Changed = et0.balanceOf(address(mainContract)) - beforeTotal0Balance;
            if (balance0Changed > item.token0Balance)
                platformFee = int256((balance0Changed - item.token0Balance) * uint256(_pairInfo.platformFeeRate) / 10000);
            if (platformFee < 0) platformFee = 0;
            item.token0Balance = balance0Changed - uint256(platformFee);
            _pairStats.totalRealToken0 += item.token0Balance;
            _pairStats.totalFeeToken0 += uint256(platformFee);
        }
        return (item, uint256(platformFee));
    }

    function create(address maker, uint256 id, uint256 extId, uint16 holdIdx, uint256 token0Balance, uint256 token1Balance) public onlyOwner returns (SwapItem memory){
        //        uint256 id = _swap_id_seq++;
        require(id > 0 && extId > 0, "ID error");
        require(swapItemExtMap[extId] == 0, "Repeat create");
        require(swapItemMap[id].id == 0, "Repeat create");
        require(swapItemMap[id].maker == address(0), "Repeat create");
        SwapItem memory item;
        item.id = id;
        item.extId = extId;
        item.enabled = true;
        item.maker = maker;
        item.costIdx = holdIdx;
        item.holdIdx = holdIdx;
        item.costToken0Quantity = token0Balance;
        item.costToken1Quantity = token1Balance;
        item.token0Balance = token0Balance;
        item.token1Balance = token1Balance;
        swapItemMap[id] = item;
        swapItemExtMap[extId] = id;
        swapItems.add(id);
        if (item.holdIdx == 0) {
            _pairStats.totalCostToken0 += token0Balance;
            _pairStats.totalRealToken0 += token0Balance;
        } else {
            _pairStats.totalCostToken1 += token1Balance;
            _pairStats.totalRealToken1 += token1Balance;
        }
        reward.plusBalance(maker, token0Balance);
        _pairStats.totalItemCount += 1;
        _pairStats.activeItemCount += 1;
        if (_firstItemId == 0)
            _firstItemId = id;
        _lastItemId = id;
        return item;
    }

    function remove(uint256 itemId) public onlyOwner returns (SwapItem memory){
        SwapItem storage item = swapItemMap[itemId];
        require(item.enabled, "disabled");
        _pairStats.activeItemCount -= 1;
        if (item.holdIdx == 0) {
            _pairStats.totalRealToken0 -= item.token0Balance;
        } else {
            _pairStats.totalRealToken1 -= item.token1Balance;
        }
        item.enabled = false;
        item.token0Balance = 0;
        item.token1Balance = 0;
        reward.minusBalance(item.maker, item.costToken0Quantity);
        swapItems.remove(itemId);
        return item;
    }

    function rewardEarned(address account) public view returns (uint256) {
        return reward.earned(account);
    }

    function rewardGet(address account) public onlyOwner {
        return reward.getReward(account);
    }
}
