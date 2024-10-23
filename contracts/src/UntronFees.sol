// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IUntronFees.sol";

/// @title Module for calculating fees in Untron protocol.
/// @author Ultrasound Labs
/// @notice This contract implements logic for calculating over fees and rates in Untron protocol.
abstract contract UntronFees is IUntronFees, OwnableUpgradeable {
    /// @notice The number of basis points in 100%.
    uint256 constant bp = 1000000; // min 0.000001 i.e 0.0001%. made for consistency with usdt decimals

    // UntronFees variables
    uint256 public relayerFee; // percents
    uint256 public fulfillerFee; // USDT L2

    function _setFeesVariables(uint256 _relayerFee, uint256 _fulfillerFee) internal {
        require(_relayerFee > 0 && _fulfillerFee > 0, "Relayer fee must be greater than zero");

        relayerFee = _relayerFee;
        fulfillerFee = _fulfillerFee;
    }

    /// @inheritdoc IUntronFees
    function setFeesVariables(uint256 _relayerFee, uint256 _fulfillerFee) external override onlyOwner {
        _setFeesVariables(_relayerFee, _fulfillerFee);
    }

    /// @notice Converts USDT Tron (size) to USDT L2 (value) based on the rate, fixed fee, and relayer fee.
    /// @param size The size of the transfer in USDT Tron.
    /// @param rate The rate of the order.
    /// @param includeRelayerFee Whether to include the relayer fee in the conversion.
    /// @param includeFulfillerFee Whether to include the fulfiller fee in the conversion.
    /// @return value The value of the transfer in USDT L2.
    /// @return fee The fee for the transfer.
    function conversion(uint256 size, uint256 rate, bool includeRelayerFee, bool includeFulfillerFee)
        internal
        view
        returns (uint256 value, uint256 fee)
    {
        // convert size into USDT L2 based on the rate
        uint256 out = (size * rate / bp);
        // if the relayer fee is included, subtract it from the converted size
        if (includeRelayerFee) {
            // subtract relayer fee from the converted size
            value = out * (bp - relayerFee) / bp;
            // and write the fee to the fee variable
            fee += out - value;
        } else {
            // if the relayer fee is not included, the value is just converted size (size * rate)
            value = out;
        }
        // subtract fixed fulfiller fee from the output value
        if (includeFulfillerFee) {
            uint256 _fulfillerFee = fulfillerFee < value ? fulfillerFee : value;
            fee += _fulfillerFee;
            value -= _fulfillerFee;
        }
    }
}
