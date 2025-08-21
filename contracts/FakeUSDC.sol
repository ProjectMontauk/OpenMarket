// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FakeUsdc is ERC20 {
    constructor() ERC20('Test USDC', 'USDC') {}
    
    uint private dummy;

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
    
    // Explicitly override inherited functions to fix viaIR issues
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }
    
    function name() public view override returns (string memory) {
        return super.name();
    }
    
    function symbol() public view override returns (string memory) {
        return super.symbol();
    }
    
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }
    
    function transfer(address to, uint256 amount) public override returns (bool) {
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        return super.transferFrom(from, to, amount);
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        return super.approve(spender, amount);
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return super.allowance(owner, spender);
    }
}