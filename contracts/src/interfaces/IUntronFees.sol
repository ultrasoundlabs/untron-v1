// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Interface for UntronFees contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronFees contract.
interface IUntronFees {
    /// @notice Updates the UntronFees-related variables
    /// @param _relayerFee The new fee charged by the relayer (in percents)
    function setFeesVariables(uint256 _relayerFee, uint256 _feePoint) external;
}
