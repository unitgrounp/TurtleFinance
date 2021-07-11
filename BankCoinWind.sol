// SPDX-License-Identifier: MIT

pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITurtleFinanceTokenPoolBank.sol";
import "./interfaces/ITurtleFinanceMainV1.sol";

library ICoinWindStructs {

    // 每个池子的信息
    struct PoolCowInfo {
        //cow 收益数据
        uint256 accCowPerShare;
        // cow累计收益
        uint256 accCowShare;
        //每个块奖励cow
        uint256 blockCowReward;
        //每个块奖励mdx
        uint256 blockMdxReward;
    }

    struct PoolInfo {
        // 用户质押币种
        address token;
        // 上一次结算收益的块高
        uint256 lastRewardBlock;
        // 上一次结算的用户总收益占比
        uint256 accMdxPerShare;
        // 上一次结算的平台分润占比
        uint256 govAccMdxPerShare;
        // 上一次结算累计的mdx收益
        uint256 accMdxShare;
        // 所有用户质押总数量
        uint256 totalAmount;
        // 所有用户质押总数量上限，0表示不限
        uint256 totalAmountLimit;
        // 用户收益率，万分之几
        uint256 profit;
        // 赚钱的最低触发额度
        uint256 earnLowerlimit;
        // 池子留下的保留金 min为100 表示 100/10000 = 1/100 = 0.01 表示 0.01%
        uint256 min;
        //单币质押年华
        uint256 lastRewardBlockProfit;
        PoolCowInfo cowInfo;
    }
}

interface ICoinWind {

    function getDepositAsset(address token, address user) external view returns (uint256);

    function deposit(address token, uint256 quantity) external;

    function withdraw(address token, uint256 quantity) external;

    function poolInfo(uint256 pid) external view returns (ICoinWindStructs.PoolInfo memory);

    function poolLength() external view returns (uint256);

    function pending(uint256 pid, address user) external view returns (uint256, uint256, uint256);

    function pendingCow(uint256 pid, address user) external view returns (uint256);
}

contract BankCoinWind is ITurtleFinanceTokenPoolBank {

    using SafeERC20 for IERC20;

    ICoinWind public coinWind;
    ITurtleFinanceMainV1 public mainContract;

    constructor(address mainAddr_, address coinWind_) {
        require(mainAddr_ != address(0), "mainAddr_ address cannot be 0");
        require(coinWind_ != address(0), "coinWind_ address cannot be 0");
        coinWind = ICoinWind(coinWind_);
        mainContract = ITurtleFinanceMainV1(mainAddr_);
    }

    modifier onlyOwner() {
        bool isOwner = mainContract.owner() == msg.sender;
        require(isOwner, "caller is not the owner");
        _;
    }
    modifier onlyMain() {
        bool isMain = address(mainContract) == msg.sender;
        require(isMain, "caller is not the main");
        _;
    }

    function _poolInfo(address token) private view returns (ICoinWindStructs.PoolInfo memory, uint256){
        uint256 len = coinWind.poolLength();
        for (uint256 i = 0; i < len; i++) {
            ICoinWindStructs.PoolInfo memory info = coinWind.poolInfo(i);
            if (info.token == token)
                return (info, i);
        }
        require(false, "BankCoinWind: pool not found");
    }

    // ----------------------- public view functions ---------------------
    function mainContractAddress() override external view returns (address){
        return address(mainContract);
    }

    function name() override external view returns (string memory){
        return "BankCoinWind";
    }

    function getProfit(address token) public view returns (uint256, uint256){
        (ICoinWindStructs.PoolInfo memory info,uint256 pid) = _poolInfo(token);
        (uint256 mdxQuantity,uint256 a2,uint256 a3) = coinWind.pending(pid, address(this));
        uint256 cowQuantity = coinWind.pendingCow(pid, address(this));
        return (mdxQuantity, cowQuantity);
    }

    // ----------------------- end public view functions ---------------------



    // ----------------------- owner functions ---------------------

    function withdrawProfit(address token, address to, address[] calldata profitTokens) onlyOwner external {
        uint256[] memory beforeBalances = new uint256[](profitTokens.length);
        for (uint i = 0; i < profitTokens.length; i++) {
            IERC20 profitTokenContract = IERC20(profitTokens[i]);
            uint256 quantity = profitTokenContract.balanceOf(address(this));
            beforeBalances[i] = quantity;
        }
        coinWind.withdraw(token, 0);
        for (uint i = 0; i < profitTokens.length; i++) {
            IERC20 profitTokenContract = IERC20(profitTokens[i]);
            uint256 quantity = profitTokenContract.balanceOf(address(this)) - beforeBalances[i];
            if (quantity > 0)
                profitTokenContract.safeTransfer(to, quantity);
        }
    }

    function withdrawToken(address token, address payable to, uint256 quantity) public onlyOwner {
        if (token == address(0))
            to.transfer(quantity);
        else
            IERC20(token).safeTransfer(to, quantity);
    }

    // ----------------------- end owner functions ---------------------



    // ----------------------- main functions ---------------------
    function create(address token) onlyMain override external {

    }

    function balanceOf(address token) onlyMain override external view returns (uint256){
        return coinWind.getDepositAsset(token, address(this));
    }

    function save(address token, uint256 quantity) onlyMain override external {
        IERC20(token).approve(address(coinWind), quantity);
        coinWind.deposit(token, quantity);
    }

    function take(address token, uint256 quantity) onlyMain override external {
        coinWind.withdraw(token, quantity);
        IERC20(token).safeTransfer(address(mainContract), quantity);
    }

    function destroy(address token) onlyMain override external {

    }
    // ----------------------- end main functions ---------------------

}