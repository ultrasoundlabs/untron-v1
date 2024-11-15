// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/UntronCore.sol";
import "../src/UntronCoreProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockSP1Verifier {
    function verifyProof(bytes32, bytes calldata, bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract DeployMainnetScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock verifier
        MockSP1Verifier mockVerifier = new MockSP1Verifier();

        // Deploy implementation
        UntronCore implementation = new UntronCore();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            UntronCore.initialize.selector,
            "" // empty genesis state
        );
        
        UntronCoreProxy proxy = new UntronCoreProxy(
            address(implementation),
            vm.addr(deployerPrivateKey), // admin
            initData
        );

        // Configure the proxy
        UntronCore untron = UntronCore(address(proxy));

        // Set core variables
        untron.setCoreVariables(
            10000 * 1e6, // maxOrderSize: 10K USDT
            0 * 1e6,    // requiredCollateral: 0 USDT
            300 * 1000    // orderTtlMillis: 5 minutes
        );

        // Set fees variables
        untron.setFeesVariables(
            0,          // relayerFee: 0%
            0.05 * 1e6  // fulfillerFee: 0.05 USDT
        );

        // Set transfers variables
        untron.setTransfersVariables(
            0x493257fD37EDB34451f62EDf8D2a0C418852bA4C, // USDT
            0x341e94069f53234fE6DabeF707aD424830525715  // LiFi
        );

        // Set ZK variables
        untron.setZKVariables(
            vm.addr(deployerPrivateKey), // trusted relayer
            address(mockVerifier),
            bytes32(0)                   // empty vkey
        );

        vm.stopBroadcast();

        console.log("Deployed UntronCore implementation at:", address(implementation));
        console.log("Deployed UntronCore proxy at:", address(proxy));
        console.log("Deployed Mock Verifier at:", address(mockVerifier));
    }
}