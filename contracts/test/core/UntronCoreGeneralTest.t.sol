// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./UntronCoreBase.t.sol";

contract UntronCoreGeneralTest is UntronCoreBase {
    constructor() UntronCoreBase() {}

    function test_setUntronCoreVariables_SetVariables() public {
        vm.startPrank(admin);

        uint256 maxOrderSize = 100e6;
        uint256 requiredCollateral = 100e6;
        uint256 orderTtlMillis = 300000;

        untron.setCoreVariables(maxOrderSize, requiredCollateral, orderTtlMillis);

        assertEq(untron.maxOrderSize(), maxOrderSize);
        assertEq(untron.requiredCollateral(), requiredCollateral);
        assertEq(untron.orderTtlMillis(), orderTtlMillis);

        vm.stopPrank();
    }

    function test_providers_GetProviderDetails() public {
        // Given
        (address provider,) = addProviderWithDefaultParams(1);
        createContext();
        
        // When
        IUntronCore.Provider memory _provider = untron.providers(provider);

        // Then
        assertEq(_provider.liquidity, 1000e6);
        assertEq(_provider.rate, 1e6);
        assertEq(_provider.minOrderSize, 10e6);
        assertEq(_provider.minDeposit, 10e6);
        assertEq(_provider.receivers.length, 1);
    }

    function test_isReceiverBusy_ChecksReceiverStatus() public {
        // Given
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        addOrderWithDefaultParams(receivers[0]);
        createContext();

        // When
        bytes32 storedOrderId = untron.isReceiverBusy(receiver);

        // Then
        assertNotEq(bytes32(0), storedOrderId);
    }

    function test_receiverOwners_GetReceiverOwner() public {
        // Given
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        createContext();

        address[] memory owners = new address[](1);

        // When
        owners[0] = untron.receiverOwners(receiver);

        // Then
        assertEq(owners.length, 1);
        assertEq(owners[0], provider);
    }

    function test_orders_GetOrderByOrderId() public {
        // Given
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator,) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];

        // When
        IUntronCore.Order memory _order = untron.orders(orderId);

        // Then
        assertEq(_order.creator, orderCreator);
        assertEq(_order.provider, provider);
        assertEq(_order.receiver, receiver);
        assertEq(_order.size, 10e6);
        assertEq(_order.rate, 1e6);
    }

    function test_changeOrder_ChangeOrder() public {
        // Given
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator,) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];

        // Change order
        vm.startPrank(orderCreator);
        IUntronTransfers.Transfer memory transfer = IUntronTransfers.Transfer({
            directTransfer: false,
            data: abi.encode(address(300))
        });

        // When
        untron.changeOrder(orderId, transfer);

        // Then
        // Check order details
        IUntronCore.Order memory _order = untron.orders(orderId);

        assertEq(_order.creator, orderCreator, "Order creator should remain the same");
        assertEq(_order.provider, provider, "Provider should remain the same");
        assertEq(_order.receiver, receiver, "Receiver should remain the same");
        assertEq(_order.size, 10e6, "Size should remain the same");
        assertEq(_order.rate, 1e6, "Rate should remain the same");
        assertEq(_order.transfer.directTransfer, false, "Direct transfer should be updated to false");
        assertEq(_order.transfer.data, abi.encode(address(300)), "Data should be updated to new address (300)");
    }

    function test_changeOrder_RevertIf_NonOrderCreatorChangesOrder() public {
        // Given
        // Set up provider and create order
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];

        // Change order
        vm.startPrank(address(300));
        IUntronTransfers.Transfer memory transfer = IUntronTransfers.Transfer({
            directTransfer: false,
            data: abi.encode(address(300))
        });

        // When
        // Try to change order as non-creator
        vm.expectRevert();
        untron.changeOrder(orderId, transfer);

        // Then
        vm.stopPrank();
    }
}
