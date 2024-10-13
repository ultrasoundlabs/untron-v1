// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/interfaces/IUntronCore.sol";
import "../../src/interfaces/IUntronTransfers.sol";
import "../../src/UntronCore.sol";
import "./../mocks/MockLifi.sol";
import "./../mocks/MockUSDT.sol";
import "../common/TestContext.sol";
import "../common/UntronCoreUtils.sol";
import "@sp1-contracts/SP1MockVerifier.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// We must do inheritance because of zkEVM constraints
// See: https://foundry-book.zksync.io/zksync-specifics/limitations/cheatcodes
// Ideally we would have test context and utils as separate contracts
abstract contract UntronCoreBase is TestContext {
    UntronCore untronImplementation;

    constructor() TestContext() {}

    // Test functions
    function setUp() public override {
        vm.warp(1725527575); // the time i did this test at
        vm.chainId(1337);

        // Remove test context from previous test if any
        tearDown();

        vm.startPrank(admin);

        bytes memory state = "hello 123";

        // Use UntronCore since UntronFees is abstract
        untronImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(UntronCore.initialize.selector, state);

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronImplementation), initData);
        untron = UntronCore(address(proxy));

        untron.setCoreVariables(1000e6, 1e6, 300000);
        untron.setFeesVariables(100, 0.01e6);
        untron.setTransfersVariables(address(usdt), address(lifi));
        untron.setZKVariables(address(420), address(sp1Verifier), bytes32(uint256(1)));

        // Setup context for next test
        contextSetup();

        vm.stopPrank();
    }

    function test_SetUp() public view {
        assertEq(untron.maxOrderSize(), 1000e6);
        assertEq(untron.requiredCollateral(), 1e6);
        assertEq(untron.genesisState(), "hello 123");
        assertEq(untron.stateHash(), sha256("hello 123"));

        assertEq(untron.owner(), admin);
    }

    // Helper function to create a transfer object
    function getTransferDetails(address orderRecipient, bool directTransfer) internal pure returns (IUntronTransfers.Transfer memory) {
        return IUntronTransfers.Transfer({
            directTransfer: directTransfer,
            data: abi.encode(orderRecipient)
        });
    }

    function bound(uint256 value, uint256 min, uint256 max) override internal pure returns (uint256) {
        if (value < min) return min;
        if (value > max) return max;
        return value;
    }
}