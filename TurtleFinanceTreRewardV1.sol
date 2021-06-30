pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract TurtleFinanceTreRewardV1 is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public tre;
    uint256 public halvePeriodTime;
    uint256 public halvePeriodRate;
    uint256 public rewardRate = 0;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public initRewardQuantity;
    uint256 public currRewardQuantity;
    uint256 public currEndTime;
    uint256 public halveCount;
    uint256 public halveMax;

    uint256 public totalBalance;
    uint256 public totalPaidReward;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public unpaidRewards;
    mapping(address => uint256) public paidRewards;
    mapping(address => uint256) public balances;

    event RewardPaid(address indexed user, uint256 reward);

    constructor(address tre_, uint256 halvePeriodTime_, uint256 halvePeriodRate_, uint256 totalRewardQuantity_, uint256 halveMax_) public {
        tre = IERC20(tre_);
        halvePeriodTime = halvePeriodTime_;
        halvePeriodRate = halvePeriodRate_;
        halveMax = halveMax_;
        initRewardQuantity = totalRewardQuantity_;
        currRewardQuantity = totalRewardQuantity_;
        rewardRate = initRewardQuantity / halvePeriodTime;
        currEndTime = block.timestamp + halvePeriodTime;
        lastUpdateTime = block.timestamp;
    }


    modifier updateHalve() {
        if (block.timestamp >= currEndTime) {
            if (halveMax > 0 && halveCount >= halveMax) return;
            currRewardQuantity = currRewardQuantity * halvePeriodRate / 10000;
            rewardRate = currRewardQuantity / halvePeriodTime;
            currEndTime = block.timestamp + halvePeriodTime;
            halveCount++;
        }
        _;
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            unpaidRewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, currEndTime);
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalBalance == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18 / totalBalance);
    }

    function earned(address account) public view returns (uint256) {
        uint256 amount = (balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18 + unpaidRewards[account];
        return amount;
    }

    function plusBalance(address account, uint256 quantity) onlyOwner updateReward(account) updateHalve public {
        balances[account] = balances[account] + quantity;
        totalBalance = totalBalance + quantity;
    }

    function minusBalance(address account, uint256 quantity) onlyOwner updateReward(account) updateHalve public {
        balances[account] = balances[account] - quantity;
        totalBalance = totalBalance - quantity;
    }

    function getReward(address account) onlyOwner updateReward(account) updateHalve public {
        uint256 reward = earned(account);
        if (reward > 0) {
            unpaidRewards[account] = 0;
            paidRewards[account] = paidRewards[account] + reward;
            tre.safeTransfer(account, reward);
            totalPaidReward = totalPaidReward + reward;
            emit RewardPaid(account, reward);
        }
    }

}
