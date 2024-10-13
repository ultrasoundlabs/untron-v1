// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ISP1Verifier} from "@sp1-contracts/ISP1Verifier.sol";
import "./interfaces/IUntronZK.sol";

/// @title Module for ZK-related logic in Untron
/// @author Ultrasound Labs
/// @notice This contract wraps ZK proof verification in a UUPS-compatible manner.
abstract contract UntronZK is IUntronZK, OwnableUpgradeable {
    // UntronZK variables
    address public trustedRelayer;
    address public verifier;
    bytes32 public vkey;

    function _setZKVariables(address _trustedRelayer, address _verifier, bytes32 _vkey) internal {
        trustedRelayer = _trustedRelayer;
        verifier = _verifier;
        vkey = _vkey;
    }

    /// @inheritdoc IUntronZK
    function setZKVariables(address _trustedRelayer, address _verifier, bytes32 _vkey) external override onlyOwner {
        _setZKVariables(_trustedRelayer, _verifier, _vkey);
    }

    /// @notice verify the ZK proof
    /// @param proof The ZK proof to verify.
    /// @param publicValues The public values to verify the proof with.
    /// @dev reverts in case the proof is invalid. Currently wraps SP1 zkVM.
    function verifyProof(bytes memory proof, bytes memory publicValues) internal view {
        if (vkey == bytes32(0)) {
            require(msg.sender == trustedRelayer, "Only trusted relayer can call this function");
            return;
        }

        ISP1Verifier(verifier).verifyProof(vkey, publicValues, proof);
    }
}
