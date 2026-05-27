// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

/// @notice A mock ERC20 that takes a fixed-percentage fee on every transfer.
/// @dev Used to verify the vault's FoT detection logic. The fee is burned
///      (sent to address(0)) so total supply stays consistent.
contract FeeOnTransferToken is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1% fee (100 basis points)
    uint256 private constant BPS_DENOMINATOR = 10_000;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Override _update to take a fee on every transfer.
    ///      _update is OpenZeppelin v5's internal transfer hook — called by
    ///      transfer, transferFrom, mint, and burn. We skip the fee on mint
    ///      (from == address(0)) and burn (to == address(0)).
    function _update(address from, address to, uint256 amount) internal override {
        if (from == address(0) || to == address(0)) {
            // Mint or burn: pass through without taking a fee
            super._update(from, to, amount);
            return;
        }

        uint256 fee = (amount * FEE_BPS) / BPS_DENOMINATOR;
        uint256 amountAfterFee = amount - fee;

        super._update(from, to, amountAfterFee);
        super._update(from, address(0), fee); // burn the fee
    }
}
