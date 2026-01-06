// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Nash (FakeUSDC for Testing)
 * @dev A test token that mimics USDC behavior for testing purposes
 * - 6 decimals (same as real USDC)
 * - Mintable for testing
 * - Standard ERC20 interface compatible with SafeERC20
 */
contract Nash is ERC20 {
    constructor() ERC20('Fake USDC', 'fUSDC') {}
    uint private dummy;

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * USDC uses 6 decimals, so we match that for accurate testing.
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev Mints tokens to an account (for testing only)
     * @param account The address to mint tokens to
     * @param amount The amount of tokens to mint (in 6 decimals)
     */
    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}