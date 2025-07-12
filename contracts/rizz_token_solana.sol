// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

@program_id("GsiDHuW2tr69MVVj56Dbmys32Tvm3UEuhcSx8asnaeS2")
contract RizzToken {
    // Token metadata
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    // SPL Token Program ID
    address constant TOKEN_PROGRAM_ID = address"TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
    
    // Balances and allowances mapping
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);
    
    // Owner of the contract
    address public owner;
    
    // Constructor
    @payer(payer)
    constructor() {
        owner = tx.accounts.payer.key;
        name = "Rizz Token";
        symbol = "RIZZ";
        decimals = 9;
        totalSupply = 10_000_000_000 * 10**9; // 1 billion tokens with 9 decimals
        
        // Mint initial supply to the contract creator
        balanceOf[tx.accounts.payer.key] = totalSupply;
        emit Transfer(address(0), tx.accounts.payer.key, totalSupply);
    }
    
    // Modifier to restrict function access to owner only
    modifier onlyOwner() {
        require(tx.accounts.payer.key == owner, "Only owner can call this function");
        _;
    }
    
    // Transfer tokens
    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[tx.accounts.payer.key] >= amount, "Insufficient balance");
        
        balanceOf[tx.accounts.payer.key] -= amount;
        balanceOf[to] += amount;
        emit Transfer(tx.accounts.payer.key, to, amount);
        return true;
    }
    
    // Approve spender to spend tokens
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Approve to zero address");
        
        allowance[tx.accounts.payer.key][spender] = amount;
        emit Approval(tx.accounts.payer.key, spender, amount);
        return true;
    }
    
    // Transfer tokens from one address to another
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][tx.accounts.payer.key] >= amount, "Insufficient allowance");
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][tx.accounts.payer.key] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
    
    // Mint new tokens (only owner)
    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        require(to != address(0), "Mint to zero address");
        
        totalSupply += amount;
        balanceOf[to] += amount;
        
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
        return true;
    }
    
    // Burn tokens
    function burn(uint256 amount) public returns (bool) {
        require(balanceOf[tx.accounts.payer.key] >= amount, "Insufficient balance");
        
        balanceOf[tx.accounts.payer.key] -= amount;
        totalSupply -= amount;
        
        emit Burn(tx.accounts.payer.key, amount);
        emit Transfer(tx.accounts.payer.key, address(0), amount);
        return true;
    }
    
    // Transfer ownership
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }
} 