// SPDX-License-Identifier: MIT

pragma solidity >0.6.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITurtleFinanceTokenPoolBank.sol";
import "./interfaces/ITurtleFinanceMainV1.sol";
import "./interfaces/IERC20Token.sol";

interface ISolo {

    /**
     * @dev Get Pool infos
     * If you want to get the pool's available quota, let "avail = depositCap - accShare"
     */
    function pools(uint256 pid) external view returns (
        address token, // Address of token contract
        uint256 depositCap, // Max deposit amount
        uint256 depositClosed, // Deposit closed
        uint256 lastRewardBlock, // Last block number that reward distributed
        uint256 accRewardPerShare, // Accumulated rewards per share
        uint256 accShare, // Accumulated Share
        uint256 apy, // APY, times 10000
        uint256 used                // How many tokens used for farming
    );

    /**
    * @dev Get pid of given token
    */
    function pidOfToken(address token) external view returns (uint256 pid);

    /**
    * @dev Get User infos
    */
    function users(uint256 pid, address user) external view returns (
        uint256 amount, // Deposited amount of user
        uint256 rewardDebt  // Ignore
    );

    /**
     * @dev Get user unclaimed reward
     */
    function unclaimedReward(uint256 pid, address user) external view returns (uint256 reward);

    /**
     * @dev Get user total claimed reward of all pools
     */
    function userStatistics(address user) external view returns (uint256 claimedReward);

    /**
     * @dev Deposit tokens and Claim rewards
     * If you just want to claim rewards, call function: "deposit(pid, 0)"
     */
    function deposit(uint256 pid, uint256 amount) external;

    /**
     * @dev Withdraw tokens
     */
    function withdraw(uint256 pid, uint256 amount) external;

}

contract BankSoloTop is ITurtleFinanceTokenPoolBank {

    using SafeERC20 for IERC20Token;

    ISolo public solo;
    address public rewardTokenAddr;
    ITurtleFinanceMainV1 public mainContract;

    constructor(address mainAddr_, address solo_, address rewardTokenAddr_) {
        solo = ISolo(solo_);
        rewardTokenAddr = rewardTokenAddr_;
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

    function _pid(address token) private view returns (uint256){
        return solo.pidOfToken(token);
    }

    // ----------------------- public view functions ---------------------
    function getProfit(address token) external view returns (uint256){
        return solo.unclaimedReward(_pid(token), address(this));
    }

    function mainContractAddress() override external view returns (address){
        return address(mainContract);
    }

    function name() override external view returns (string memory){
        IERC20Token tc = IERC20Token(rewardTokenAddr);
        return string(abi.encodePacked("BankSoloTop-", tc.symbol()));
    }
    // ----------------------- end public view functions ---------------------



    // ----------------------- owner functions ---------------------
    function withdrawProfit(address token, address to) onlyOwner external {
        IERC20Token tc = IERC20Token(rewardTokenAddr);
        uint256 beforeQuantity = tc.balanceOf(address(this));
        solo.deposit(_pid(token), 0);
        uint256 quantity = tc.balanceOf(address(this)) - beforeQuantity;
        tc.safeTransfer(to, quantity);
    }

    function withdrawToken(address token, address payable to, uint256 quantity) public onlyOwner {
        if (token == address(0))
            to.transfer(quantity);
        else
            IERC20Token(token).safeTransfer(to, quantity);
    }

    // ----------------------- end owner functions ---------------------



    // ----------------------- main functions ---------------------
    function create(address token) onlyMain override external {

    }

    function balanceOf(address token) onlyMain override external view returns (uint256){
        (uint256 amount,uint256 rewardDebt) = solo.users(_pid(token), address(this));
        return amount;
    }

    function save(address token, uint256 quantity) onlyMain override external {
        IERC20Token(token).approve(address(solo), quantity);
        solo.deposit(_pid(token), quantity);
    }

    function take(address token, uint256 quantity) onlyMain override external {
        solo.withdraw(_pid(token), quantity);
        IERC20Token(token).safeTransfer(address(mainContract), quantity);
    }

    function destroy(address token) onlyMain override external {

    }
    // ----------------------- end main functions ---------------------

}