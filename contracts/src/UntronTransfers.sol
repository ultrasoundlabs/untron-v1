// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IUntronTransfers.sol";

/// @title Extensive pausable transfer module for Untron
/// @author Ultrasound Labs
/// @notice This module is responsible for handling all the transfers in the Untron protocol.
/// @dev Transfer, within Untron terminology (unless specified otherwise: USDT transfer, Tron transfer, etc),
///      is the process of order creator receiving the coins in the L2 ecosystem for the USDT Tron they sent.
///      Natively, these tokens are USDT L2 (on ZKsync Era, Untron's host chain).
///      However, the module is designed to be as chain- and coin-agnostic as possible,
///      so it supports on-the-fly swaps of USDT L2 to other coins and cross-chain transfers through Across bridge.
///      Only this module must be used to manage the funds in the Untron protocol,
///      as it contains the pausing logic in case of emergency.
abstract contract UntronTransfers is IUntronTransfers, Initializable, PausableUpgradeable, OwnableUpgradeable {
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // UntronTransfers variables
    address public usdt;
    address public lifi;

    function _setTransfersVariables(address _usdt, address _lifi) internal {
        usdt = _usdt;
        lifi = _lifi;
    }

    /// @inheritdoc IUntronTransfers
    function setTransfersVariables(address _usdt, address _lifi) external override onlyOwner {
        _setTransfersVariables(_usdt, _lifi);
    }

    /// @notice Performs the transfer.
    /// @param transfer The transfer details.
    /// @param amount The amount of USDT to transfer.
    function smartTransfer(Transfer memory transfer, uint256 amount) internal whenNotPaused returns (bool success) {
        // if the transfer is into USDT on the same chain, perform an internal transfer
        if (transfer.directTransfer) {
            internalTransfer(usdt, abi.decode(transfer.data, (address)), amount);
            success = true;
        } else {
            // otherwise, perform a cross-chain transfer through the LiFi Diamond contract.
            // see https://docs.li.fi/smart-contracts/overview for reference

            // approving the token to lifi contract
            IERC20(usdt).approve(lifi, amount);

            (success,) = lifi.call(transfer.data);
        }
    }

    /// @notice perform a native (onchain) ERC20 transfer
    /// @param token the token address
    /// @param to the recipient address
    /// @param amount the amount of USDT to transfer
    /// @dev transfers ERC20 token to "to" address.
    ///      needed for fulfiller/relayer-related operations and inside the smartTransfer function.
    function internalTransfer(address token, address to, uint256 amount) internal whenNotPaused {
        require(IERC20(token).transfer(to, amount));
    }

    /// @notice perform a native (USDT on ZKsync Era) ERC20 transferFrom
    /// @param from the sender address
    /// @param amount the amount of USDT to transfer
    /// @dev transfers USDT zksync from "from" to this contract.
    ///      needed for fulfiller/relayer-related operations and inside the smartTransfer function.
    function internalTransferFrom(address from, uint256 amount) internal whenNotPaused {
        require(IERC20(usdt).transferFrom(from, address(this), amount));
    }
}
