// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

/// @title Tool functions for Untron
/// @author Ultrasound Labs
/// @notice This contract contains various utility functions used across the Untron protocol.
abstract contract UntronTools {
    /// @notice Returns the chain ID of the current network.
    /// @return _chainId The chain ID.
    function chainId() internal view returns (uint256 _chainId) {
        assembly {
            _chainId := chainid()
        }
    }

    /// @notice Converts a Unix timestamp to a Tron timestamp.
    /// @param _timestamp The Unix timestamp to convert.
    /// @return uint256 The timestamp in Tron's format.
    /// @dev There's no guarantee Tron's clocks won't be rolled back in the future,
    ///      so this might break the system and must be carefully checked.
    function unixToTron(uint256 _timestamp) internal pure returns (uint256) {
        // Tron uses god knows what format for timestamping
        // and this formula is an approximation.
        // i only figured out that it's in milliseconds
        // because timestamps in blocks differ by 3000 and are created every 3 secs IRL.
        // CALCULATION FOR THE SUBTRAHEND:
        // blockheader(62913164).raw_data.timestamp - (tronscan(62913164).timestamp * 1000)
        return _timestamp * 1000 - 170539755000;
    }
}
