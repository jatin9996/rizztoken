// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

@program_id("Stak1ngPr0gramHere111111111111111111111111")
contract StakingContract {
    // Reference to the token contract
    address public tokenAddress;
    
    // Staking info structure
    struct StakeInfo {
        uint256 amount;           // Amount of tokens staked
        uint64 startTime;         // Time when staking started
        uint256 rewardDebt;       // Reward debt for reward calculation
    }
    
    // Mapping from staker address to their staking info
    mapping(address => StakeInfo) public stakes;
    
    // Total staked amount
    uint256 public totalStaked;
    
    // Reward rate per second (in token units with decimals)
    uint256 public rewardRate;
    
    // Last update time for reward calculations
    uint64 public lastUpdateTime;
    
    // Accumulated rewards per share (scaled by 1e12 for precision)
    uint256 public accRewardPerShare;
    
    // Precision factor for calculations
    uint256 private constant PRECISION_FACTOR = 1e12;
    
    // Minimum staking period in seconds
    uint64 public minimumStakingPeriod;
    
    // Owner of the contract
    address public owner;
    
    // Events
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);
    
    // Constructor
    @payer(payer)
    constructor(address _tokenAddress, uint256 _rewardRate, uint64 _minimumStakingPeriod) {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        tokenAddress = _tokenAddress;
        rewardRate = _rewardRate;
        minimumStakingPeriod = _minimumStakingPeriod;
        lastUpdateTime = uint64(block.timestamp);
        owner = tx.accounts.payer.key;
    }
    
    // Modifier to restrict function access to owner only
    modifier onlyOwner() {
        require(tx.accounts.payer.key == owner, "Only owner can call this function");
        _;
    }
    
    // Modifier to update rewards for a user
    modifier updateReward(address account) {
        // Update accumulated reward per share
        if (totalStaked > 0) {
            uint256 timeDiff = block.timestamp - lastUpdateTime;
            uint256 reward = timeDiff * rewardRate;
            accRewardPerShare += (reward * PRECISION_FACTOR) / totalStaked;
        }
        lastUpdateTime = uint64(block.timestamp);
        
        // Update user's reward debt if they have a stake
        if (account != address(0)) {
            StakeInfo storage stakeInfo = stakes[account];
            uint256 pending = (stakeInfo.amount * accRewardPerShare) / PRECISION_FACTOR - stakeInfo.rewardDebt;
            if (pending > 0) {
                bool success = RizzToken(tokenAddress).transfer(account, pending);
                require(success, "Reward transfer failed");
                emit RewardPaid(account, pending);
            }
            stakeInfo.rewardDebt = (stakeInfo.amount * accRewardPerShare) / PRECISION_FACTOR;
        }
        _;
    }
    
    // Stake tokens
    function stake(uint256 amount) external updateReward(tx.accounts.payer.key) {
        require(amount > 0, "Cannot stake 0 tokens");
        
        StakeInfo storage stakeInfo = stakes[tx.accounts.payer.key];
        
        // If already staking, update the stake
        if (stakeInfo.amount > 0) {
            stakeInfo.amount += amount;
        } else {
            // New stake
            stakeInfo.amount = amount;
            stakeInfo.startTime = uint64(block.timestamp);
        }
        
        // Update reward debt
        stakeInfo.rewardDebt = (stakeInfo.amount * accRewardPerShare) / PRECISION_FACTOR;
        
        // Update total staked
        totalStaked += amount;
        
        // Transfer tokens from user to this contract
        bool success = RizzToken(tokenAddress).transferFrom(tx.accounts.payer.key, address(this), amount);
        require(success, "Token transfer failed");
        
        emit Staked(tx.accounts.payer.key, amount);
    }
    
    // Unstake tokens
    function unstake(uint256 amount) external updateReward(tx.accounts.payer.key) {
        StakeInfo storage stakeInfo = stakes[tx.accounts.payer.key];
        require(stakeInfo.amount >= amount, "Insufficient staked amount");
        require(block.timestamp >= stakeInfo.startTime + minimumStakingPeriod, "Minimum staking period not reached");
        
        // Update stake info
        stakeInfo.amount -= amount;
        stakeInfo.rewardDebt = (stakeInfo.amount * accRewardPerShare) / PRECISION_FACTOR;
        
        // Update total staked
        totalStaked -= amount;
        
        // Transfer tokens back to user
        bool success = RizzToken(tokenAddress).transfer(tx.accounts.payer.key, amount);
        require(success, "Token transfer failed");
        
        emit Unstaked(tx.accounts.payer.key, amount);
    }
    
    // Get pending rewards for a user
    function pendingRewards(address user) public view returns (uint256) {
        StakeInfo storage stakeInfo = stakes[user];
        if (stakeInfo.amount == 0) {
            return 0;
        }
        
        uint256 _accRewardPerShare = accRewardPerShare;
        
        // Calculate updated accRewardPerShare if there are staked tokens
        if (totalStaked > 0 && block.timestamp > lastUpdateTime) {
            uint256 timeDiff = block.timestamp - lastUpdateTime;
            uint256 reward = timeDiff * rewardRate;
            _accRewardPerShare += (reward * PRECISION_FACTOR) / totalStaked;
        }
        
        return (stakeInfo.amount * _accRewardPerShare) / PRECISION_FACTOR - stakeInfo.rewardDebt;
    }
    
    // Claim rewards without unstaking
    function claimRewards() external updateReward(tx.accounts.payer.key) {
        // The updateReward modifier handles the reward distribution
        // This function is just a convenience for users to claim rewards without unstaking
    }
    
    // Update reward rate (only owner)
    function updateRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }
    
    // Update minimum staking period (only owner)
    function updateMinimumStakingPeriod(uint64 newPeriod) external onlyOwner {
        minimumStakingPeriod = newPeriod;
    }
    
    // Emergency withdraw function for owner (in case of issues)
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        bool success = RizzToken(tokenAddress).transfer(owner, amount);
        require(success, "Token transfer failed");
    }
    
    // Fund the contract with rewards (only owner)
    function fundRewards(uint256 amount) external onlyOwner {
        bool success = RizzToken(tokenAddress).transferFrom(tx.accounts.payer.key, address(this), amount);
        require(success, "Token transfer failed");
    }
    
    // Get staking info for a user
    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint64 startTime,
        uint256 pendingReward
    ) {
        StakeInfo storage stakeInfo = stakes[user];
        return (
            stakeInfo.amount,
            stakeInfo.startTime,
            pendingRewards(user)
        );
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }
} 