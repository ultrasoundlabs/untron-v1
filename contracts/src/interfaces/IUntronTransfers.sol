// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronTransfers
/// @author Ultrasound Labs
/// @notice This interface defines the functions and events related to Untron transfers.
interface IUntronTransfers {
    /// @notice Struct representing a transfer.
    struct Transfer {
        bool directTransfer;
        // abi.encode(address) in case of directTransfer,
        // otherwise the input data for the call of Li.Fi diamond.
        bytes data;
    }

    /// @notice Updates the UntronTransfers-related variables
    /// @param _usdt The new address of the USDT token
    /// @param _lifi The new address of the LiFi Diamond contract
    function setTransfersVariables(address _usdt, address _lifi) external;
}
