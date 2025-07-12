// SPDX-License-Identifier: MIT
@program_id("Vest1ngPr0gramHere111111111111111111111111")
contract VestingContract {
    // Reference to the token program
    address public tokenProgram;
    
    // Vesting schedule structure
    struct VestingSchedule {
        uint256 totalAmount;       // Total amount of tokens to be vested
        uint256 releasedAmount;    // Amount of tokens already released
        uint64 startTime;          // Start time of the vesting period
        uint64 endTime;            // End time of the vesting period
        uint64 cliff;              // Cliff period in seconds
        bool revocable;            // Whether the vesting is revocable or not
        bool revoked;              // Whether the vesting has been revoked
    }
    
    // Mapping from beneficiary address to their vesting schedule
    mapping(address => VestingSchedule) public vestingSchedules;
    
    // Total amount of tokens in all vesting schedules
    uint256 public totalVestingAmount;
    
    // Owner of the contract
    address public owner;
    
    // Events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount, uint64 startTime, uint64 endTime, uint64 cliff);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary);
    
    // Constructor
    @payer(payer)
    constructor(address _tokenProgram) {
        require(_tokenProgram != address(0), "Token program cannot be zero");
        tokenProgram = _tokenProgram;
        owner = tx.accounts.signer.key;
        print("Vesting Contract deployed successfully!");
    }
    
    // Modifier to restrict function access to owner only
    modifier onlyOwner() {
        require(tx.accounts.signer.key == owner, "Only owner can call this function");
        _;
    }
    
    // Create a new vesting schedule for a beneficiary
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint64 startTime,
        uint64 durationInSeconds,
        uint64 cliffInSeconds,
        bool revocable
    ) external onlyOwner {
        require(beneficiary != address(0), "Beneficiary cannot be zero address");
        require(amount > 0, "Amount must be greater than zero");
        require(vestingSchedules[beneficiary].totalAmount == 0, "Vesting schedule already exists");
        
        uint64 endTime = startTime + durationInSeconds;
        
        // Create vesting schedule
        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            releasedAmount: 0,
            startTime: startTime,
            endTime: endTime,
            cliff: startTime + cliffInSeconds,
            revocable: revocable,
            revoked: false
        });
        
        // Update total vesting amount
        totalVestingAmount += amount;
        
        // Transfer tokens from owner to this contract
        // Note: Owner must approve this contract to spend tokens first
        bool success = TokenProgram(tokenProgram).transferFrom(
            tx.accounts.signer.key,
            address(this),
            amount
        );
        require(success, "Token transfer failed");
        
        emit VestingScheduleCreated(beneficiary, amount, startTime, endTime, startTime + cliffInSeconds);
    }
    
    // Calculate the releasable amount of tokens for a beneficiary
    function calculateReleasableAmount(address beneficiary) public view returns (uint256) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        // If no schedule or revoked, return 0
        if (schedule.totalAmount == 0 || schedule.revoked) {
            return 0;
        }
        
        // If current time is before cliff, return 0
        if (clock.unix_timestamp < schedule.cliff) {
            return 0;
        }
        
        // If current time is after end time, return all remaining tokens
        if (clock.unix_timestamp >= schedule.endTime) {
            return schedule.totalAmount - schedule.releasedAmount;
        }
        
        // Calculate vested amount based on linear vesting
        uint256 timeFromStart = clock.unix_timestamp - schedule.startTime;
        uint256 totalVestingTime = schedule.endTime - schedule.startTime;
        uint256 vestedAmount = (schedule.totalAmount * timeFromStart) / totalVestingTime;
        
        return vestedAmount - schedule.releasedAmount;
    }
    
    // Release vested tokens to beneficiary
    function release() external {
        address beneficiary = tx.accounts.signer.key;
        uint256 releasableAmount = calculateReleasableAmount(beneficiary);
        require(releasableAmount > 0, "No tokens are due for release");
        
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        
        // Update released amount
        schedule.releasedAmount += releasableAmount;
        
        // Transfer tokens to beneficiary
        bool success = TokenProgram(tokenProgram).transfer(
            beneficiary,
            releasableAmount
        );
        require(success, "Token transfer failed");
        
        emit TokensReleased(beneficiary, releasableAmount);
    }
    
    // Revoke vesting schedule (only for revocable schedules)
    function revoke(address beneficiary) external onlyOwner {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule found for beneficiary");
        require(schedule.revocable, "Vesting schedule is not revocable");
        require(!schedule.revoked, "Vesting schedule already revoked");
        
        // Calculate the unreleased tokens
        uint256 releasableAmount = calculateReleasableAmount(beneficiary);
        
        // Update schedule
        schedule.revoked = true;
        
        // If there are releasable tokens, release them first
        if (releasableAmount > 0) {
            schedule.releasedAmount += releasableAmount;
            bool success = TokenProgram(tokenProgram).transfer(
                beneficiary,
                releasableAmount
            );
            require(success, "Token release transfer failed");
            emit TokensReleased(beneficiary, releasableAmount);
        }
        
        // Calculate remaining tokens (not vested yet)
        uint256 remainingTokens = schedule.totalAmount - schedule.releasedAmount;
        
        // Return remaining tokens to owner
        if (remainingTokens > 0) {
            bool success = TokenProgram(tokenProgram).transfer(
                owner,
                remainingTokens
            );
            require(success, "Token return transfer failed");
        }
        
        // Update total vesting amount
        totalVestingAmount -= remainingTokens;
        
        emit VestingRevoked(beneficiary);
    }
    
    // Get vesting schedule information
    function getVestingSchedule(address beneficiary) external view returns (
        uint256 totalAmount,
        uint256 releasedAmount,
        uint64 startTime,
        uint64 endTime,
        uint64 cliff,
        bool revocable,
        bool revoked
    ) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        return (
            schedule.totalAmount,
            schedule.releasedAmount,
            schedule.startTime,
            schedule.endTime,
            schedule.cliff,
            schedule.revocable,
            schedule.revoked
        );
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }
} 