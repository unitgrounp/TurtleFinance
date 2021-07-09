pragma solidity ^0.8.5;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract TurtleFinanceTreRewardV1 is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    IERC20 public tre;
    uint256 private pool_id_seq_;
    uint256 public totalBalance;
    mapping(address => uint256) public balances;

    struct Pool {
        uint256 id;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 totalRewardQuantity;
        uint256 startTime;
        uint256 endTime;
        uint256 totalPaidReward;
    }

    mapping(uint256 => mapping(address => uint256)) private userRewardPerTokenPaid;
    mapping(uint256 => mapping(address => uint256)) private unpaidRewards;
    mapping(uint256 => mapping(address => uint256)) private paidRewards;
    mapping(uint256 => Pool) private pools;

    EnumerableSet.UintSet private poolIdList;

    event RewardPaid(uint256 pool, address indexed user, uint256 reward);

    constructor(address tre_) public {
        require(tre_ != address(0), "tre_ address cannot be 0");
        tre = IERC20(tre_);
        pool_id_seq_ = 1;
    }


    function updateReward(uint256 pid, address account) private {
        Pool storage pool = pools[pid];
        if (pool.startTime > block.timestamp) return;
        pool.rewardPerTokenStored = rewardPerToken(pid);
        pool.lastUpdateTime = lastTimeRewardApplicable(pid);
        if (account != address(0)) {
            unpaidRewards[pool.id][account] = earnedByPool(pid, account);
            userRewardPerTokenPaid[pool.id][account] = pool.rewardPerTokenStored;
        }
    }

    function addPool(address sender, uint256 totalRewardQuantity_, uint256 startTime, uint256 periodTime) public onlyOwner {
        require(startTime >= block.timestamp, "startTime < now");
        require(periodTime >= 60, "periodTime < 60");
        tre.transferFrom(sender, address(this), totalRewardQuantity_);
        Pool memory pool;
        pool.id = pool_id_seq_++;
        pool.totalRewardQuantity = totalRewardQuantity_;
        pool.rewardRate = totalRewardQuantity_ / periodTime;
        pool.startTime = startTime;
        pool.endTime = startTime + periodTime;
        pool.lastUpdateTime = startTime;
        pools[pool.id] = pool;
        poolIdList.add(pool.id);
    }

    // ---------------------- view functions -------------------------
    function getPools() public view returns (Pool[] memory){
        uint256 len = poolIdList.length();
        Pool[] memory _pools = new Pool[](len);
        for (uint i = 0; i < len; i++) {
            _pools[i] = pools[poolIdList.at(i)];
        }
        return _pools;
    }

    function lastTimeRewardApplicable(uint256 pid) public view returns (uint256) {
        if (block.timestamp < pools[pid].startTime) return pools[pid].startTime;
        return Math.min(block.timestamp, pools[pid].endTime);
    }

    function rewardPerToken(uint256 pid) public view returns (uint256) {
        if (totalBalance == 0) {
            return pools[pid].rewardPerTokenStored;
        }
        return pools[pid].rewardPerTokenStored + ((lastTimeRewardApplicable(pid) - pools[pid].lastUpdateTime) * pools[pid].rewardRate * 1e18 / totalBalance);
    }

    function earnedByPool(uint256 pid, address account) public view returns (uint256) {
        if (pools[pid].startTime > block.timestamp) return 0;
        uint256 urptp = userRewardPerTokenPaid[pid][account];
        uint256 amount = (balances[account] * (rewardPerToken(pid) - urptp)) / 1e18 + unpaidRewards[pid][account];
        return amount;
    }

    function earned(address account) public view returns (uint256) {
        uint256 earned_ = 0;
        uint256 len = poolIdList.length();
        for (uint i = 0; i < len; i++) {
            earned_ += earnedByPool(poolIdList.at(i), account);
        }
        return earned_;
    }
    // ---------------------- end view functions -------------------------

    function plusBalance(address account, uint256 quantity) onlyOwner public {
        require(account != address(0), "account address cannot be 0");
        uint256 len = poolIdList.length();
        for (uint i = 0; i < len; i++) {
            updateReward(poolIdList.at(i), account);
        }
        balances[account] = balances[account] + quantity;
        totalBalance = totalBalance + quantity;
    }

    function minusBalance(address account, uint256 quantity) onlyOwner public {
        require(account != address(0), "account address cannot be 0");
        uint256 len = poolIdList.length();
        for (uint i = 0; i < len; i++) {
            updateReward(poolIdList.at(i), account);
        }
        balances[account] = balances[account] - quantity;
        totalBalance = totalBalance - quantity;
    }

    function getRewardByPool(uint256 pid, address account) onlyOwner public {
        updateReward(pid, account);
        uint256 reward = earnedByPool(pid, account);
        if (reward > 0) {
            unpaidRewards[pid][account] = 0;
            paidRewards[pid][account] = paidRewards[pid][account] + reward;
            pools[pid].totalPaidReward = pools[pid].totalPaidReward + reward;
            tre.safeTransfer(account, reward);
            emit RewardPaid(pid, account, reward);
        }
    }

    function getReward(address account) onlyOwner public {
        uint256 len = poolIdList.length();
        for (uint i = 0; i < len; i++) {
            getRewardByPool(poolIdList.at(i), account);
        }
    }

}
