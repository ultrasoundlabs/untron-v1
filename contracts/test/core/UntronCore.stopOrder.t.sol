// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./UntronCoreBase.t.sol";

abstract contract StopOrderTest is UntronCoreBase {
    constructor() UntronCoreBase() {}
    
    address provider = vm.addr(111);
    address orderCreator = vm.addr(777);

    event OrderStopped(bytes32 indexed orderId);

    // Test: Successfully stopping an order
    function test_stopOrder_Success() public {
        // Given
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Stop the order
        bytes32 orderId = result.orderIds[0];

        vm.expectEmit(true, true, true, true);
        emit OrderStopped(orderId);

        vm.startPrank(orderCreator);
        untron.stopOrder(orderId);
        vm.stopPrank();

        // Assert: Order is deleted, liquidity refunded, and collateral returned
        IUntronCore.Order memory stoppedOrder = untron.orders(orderId);
        assertEq(stoppedOrder.creator, address(0), "Order should be deleted");
        assertEq(untron.isReceiverBusy(receivers[0]), bytes32(0), "Receiver should be freed");

        IUntronCore.Provider memory providerInfo = untron.providers(provider);
        assertEq(providerInfo.liquidity, 1000e6, "Liquidity should be refunded to provider");

        uint256 collateralBalance = usdt.balanceOf(orderCreator);
        assertEq(collateralBalance, untron.requiredCollateral(), "Collateral should be refunded to order creator");
    }

    // Test: Revert if caller is not the order creator
    function test_stopOrder_RevertIf_NotOrderCreator() public {
        // Given
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        createContext();

        // Attempt to stop the order from an unauthorized address
        bytes32 orderId = untron.isReceiverBusy(receivers[0]);

        vm.startPrank(vm.addr(200)); // Not the order creator
        vm.expectRevert("Only creator can stop the order");
        untron.stopOrder(orderId);
        vm.stopPrank();
    }

    // Test: Revert if the order has been fulfilled
    function test_stopOrder_RevertIf_OrderFulfilled() public {
        // Given
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addFulfilledOrderWithDefaultParams(receivers[0]);
        createContext();

        // Attempt to stop a fulfilled order
        bytes32 orderId = untron.isReceiverBusy(receivers[0]);

        vm.startPrank(orderCreator);
        vm.expectRevert("Order has been fulfilled");
        untron.stopOrder(orderId);
        vm.stopPrank();
    }

    // Test: Revert if order does not exist
    function test_stopOrder_RevertIf_OrderDoesNotExist() public {
        bytes32 fakeOrderId = keccak256(abi.encodePacked("nonexistent order"));

        vm.startPrank(orderCreator);
        vm.expectRevert();
        untron.stopOrder(fakeOrderId);
        vm.stopPrank();
    }

    // TODO: Revert if stopping order that is expired (code not implemented yet)
    function test_stopOrder_RevertIf_OrderExpired() public {
       // TODO: Implement this test
    }

    // Additional invariant and fuzz tests as needed...
}