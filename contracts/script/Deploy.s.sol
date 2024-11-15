// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/UntronCore.sol";
import "../src/UntronCoreProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock contracts for testing
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}

contract MockLiFi {
    function call(bytes calldata) external returns (bool) {
        return true;
    }
}

contract MockSP1Verifier {
    function verifyProof(bytes32, bytes calldata, bytes calldata) external pure returns (bool) {
        return true;
    }
}

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock contracts
        MockUSDT mockUSDT = new MockUSDT();
        MockLiFi mockLiFi = new MockLiFi();
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
            1000000 * 1e6, // maxOrderSize: 1M USDT
            1000 * 1e6,    // requiredCollateral: 1000 USDT
            3600 * 1000    // orderTtlMillis: 1 hour
        );

        // Set fees variables
        untron.setFeesVariables(
            1000,          // relayerFee: 0.1%
            10 * 1e6      // fulfillerFee: 10 USDT
        );

        // Set transfers variables
        untron.setTransfersVariables(
            address(mockUSDT),
            address(mockLiFi)
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
        console.log("Deployed Mock USDT at:", address(mockUSDT));
        console.log("Deployed Mock LiFi at:", address(mockLiFi));
        console.log("Deployed Mock Verifier at:", address(mockVerifier));
    }
}