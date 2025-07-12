// SPDX-License-Identifier: MIT
@program_id("SwapPr0gramHere1111111111111111111111111111")

contract SwapContract {
    // Token addresses
    address public rizzTokenAddress;
    address public stableCoinAddress;
    
    // Exchange rate (how many RIZZ tokens for 1 stablecoin)
    // Scaled by 1e9 for precision
    uint256 public exchangeRate;
    
    // Fee percentage (in basis points, 1 bp = 0.01%)
    uint16 public feeRate;
    
    // Fee collector address
    address public feeCollector;
    
    // Owner of the contract
    address public owner;
    
    // Events
    event SwapRizzToStable(address indexed user, uint256 rizzAmount, uint256 stableAmount, uint256 fee);
    event SwapStableToRizz(address indexed user, uint256 stableAmount, uint256 rizzAmount, uint256 fee);
    event ExchangeRateUpdated(uint256 newRate);
    event FeeRateUpdated(uint16 newFeeRate);
    event FeeCollectorUpdated(address newFeeCollector);
    
    // Constructor
    @payer(payer)
    constructor(
        address _rizzTokenAddress,
        address _stableCoinAddress,
        uint256 _initialExchangeRate,
        uint16 _initialFeeRate,
        address _feeCollector
    ) {
        require(_rizzTokenAddress != address(0), "RIZZ token address cannot be zero");
        require(_stableCoinAddress != address(0), "Stablecoin address cannot be zero");
        require(_feeCollector != address(0), "Fee collector address cannot be zero");
        require(_initialFeeRate <= 1000, "Fee rate cannot exceed 10%");
        
        rizzTokenAddress = _rizzTokenAddress;
        stableCoinAddress = _stableCoinAddress;
        exchangeRate = _initialExchangeRate;
        feeRate = _initialFeeRate;
        feeCollector = _feeCollector;
        owner = tx.accounts.payer.key;
        
        print("Swap Contract deployed successfully!");
    }
    
    // Modifier to restrict function access to owner only
    modifier onlyOwner() {
        require(tx.accounts.payer.key == owner, "Only owner can call this function");
        _;
    }
    
    // Swap RIZZ tokens for stablecoins
    function swapRizzToStable(uint256 rizzAmount) external returns (uint256) {
        require(rizzAmount > 0, "Amount must be greater than zero");
        
        // Calculate the equivalent stable amount based on exchange rate
        // exchangeRate is how many RIZZ for 1 stable
        uint256 stableAmount = (rizzAmount * 1e9) / exchangeRate;
        
        // Calculate fee
        uint256 fee = (stableAmount * feeRate) / 10000;
        uint256 stableAmountAfterFee = stableAmount - fee;
        
        // Transfer RIZZ tokens from user to this contract
        bool success = TokenInterface(rizzTokenAddress).transferFrom(
            tx.accounts.payer.key,
            address(this),
            rizzAmount
        );
        require(success, "RIZZ token transfer failed");
        
        // Transfer stablecoins to user
        success = TokenInterface(stableCoinAddress).transfer(
            tx.accounts.payer.key,
            stableAmountAfterFee
        );
        require(success, "Stablecoin transfer failed");
        
        // Transfer fee to fee collector
        if (fee > 0) {
            success = TokenInterface(stableCoinAddress).transfer(feeCollector, fee);
            require(success, "Fee transfer failed");
        }
        
        emit SwapRizzToStable(tx.accounts.payer.key, rizzAmount, stableAmountAfterFee, fee);
        
        return stableAmountAfterFee;
    }
    
    // Swap stablecoins for RIZZ tokens
    function swapStableToRizz(uint256 stableAmount) external returns (uint256) {
        require(stableAmount > 0, "Amount must be greater than zero");
        
        // Calculate the equivalent RIZZ amount based on exchange rate
        uint256 rizzAmount = (stableAmount * exchangeRate) / 1e9;
        
        // Calculate fee
        uint256 fee = (rizzAmount * feeRate) / 10000;
        uint256 rizzAmountAfterFee = rizzAmount - fee;
        
        // Transfer stablecoins from user to this contract
        bool success = TokenInterface(stableCoinAddress).transferFrom(
            tx.accounts.payer.key,
            address(this),
            stableAmount
        );
        require(success, "Stablecoin transfer failed");
        
        // Transfer RIZZ tokens to user
        success = TokenInterface(rizzTokenAddress).transfer(
            tx.accounts.payer.key,
            rizzAmountAfterFee
        );
        require(success, "RIZZ token transfer failed");
        
        // Transfer fee to fee collector
        if (fee > 0) {
            success = TokenInterface(rizzTokenAddress).transfer(feeCollector, fee);
            require(success, "Fee transfer failed");
        }
        
        emit SwapStableToRizz(tx.accounts.payer.key, stableAmount, rizzAmountAfterFee, fee);
        
        return rizzAmountAfterFee;
    }
    
    // Get quote for swapping RIZZ to stable
    function getQuoteRizzToStable(uint256 rizzAmount) external view returns (uint256 stableAmount, uint256 fee) {
        stableAmount = (rizzAmount * 1e9) / exchangeRate;
        fee = (stableAmount * feeRate) / 10000;
        return (stableAmount - fee, fee);
    }
    
    // Get quote for swapping stable to RIZZ
    function getQuoteStableToRizz(uint256 stableAmount) external view returns (uint256 rizzAmount, uint256 fee) {
        rizzAmount = (stableAmount * exchangeRate) / 1e9;
        fee = (rizzAmount * feeRate) / 10000;
        return (rizzAmount - fee, fee);
    }
    
    // Update exchange rate (only owner)
    function updateExchangeRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Exchange rate must be greater than zero");
        exchangeRate = newRate;
        emit ExchangeRateUpdated(newRate);
    }
    
    // Update fee rate (only owner)
    function updateFeeRate(uint16 newFeeRate) external onlyOwner {
        require(newFeeRate <= 1000, "Fee rate cannot exceed 10%");
        feeRate = newFeeRate;
        emit FeeRateUpdated(newFeeRate);
    }
    
    // Update fee collector (only owner)
    function updateFeeCollector(address newFeeCollector) external onlyOwner {
        require(newFeeCollector != address(0), "Fee collector cannot be zero address");
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(newFeeCollector);
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }
}

// Interface for token operations
interface TokenInterface {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
} 