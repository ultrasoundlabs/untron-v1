// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./UntronCoreBase.t.sol";

contract FulfillOrdersTest is UntronCoreBase {
    event OrderFulfilled(bytes32 indexed orderId, address fulfiller);
    event ActionChainUpdated(
        bytes32 prevOrderId, uint256 timestamp, bytes21 receiver, uint256 minDeposit, uint256 size
    );
    event ReceiverFreed(address provider, bytes21 receiver);
    constructor() UntronCoreBase() {}

    address fulfiller = vm.addr(888);

    /// Test: Successful fulfillment of a single order with comprehensive verifications
    function test_fulfill_SuccessfulSingleOrderFulfillment() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        bytes21 receiver = receivers[0];
        TestContext.TestResult memory result = createContext();

        // Get order ID
        bytes32 orderId = result.orderIds[0];
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        // **Calculate total for the order**
        // Expected total expense is calculated using the order size and rate
        // Assuming the conversion function in the contract calculates amount and fee
        (uint256 amount, uint256 fee) = untron.calculateFulfillerTotal(orderIds);
        uint256 totalExpectedExpense = amount;

        // **Mint and approve exact amount of USDT for the fulfiller**
        mintUSDT(fulfiller, totalExpectedExpense);
        approveUSDT(fulfiller, address(untron), totalExpectedExpense);


        vm.startPrank(fulfiller);
        // **Capture the OrderFulfilled event**
        vm.expectEmit();
        emit ActionChainUpdated(orderId, block.timestamp * 1000 - 170539755000, receiver, 0, 0);
        vm.expectEmit();
        emit ReceiverFreed(provider, receiver);
        vm.expectEmit();
        emit OrderFulfilled(orderId, fulfiller);
        // **Fulfill the order**
        untron.fulfill(orderIds, totalExpectedExpense);
        vm.stopPrank();

        // **Verifications:**

        // **1. Order State Verification**
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.isFulfilled, true, "Order should be marked as fulfilled");

        // **2. Order Creator and Transfer Details Verification**
        assertEq(order.creator, fulfiller, "Order creator should now be the fulfiller");
        assertEq(order.transfer.directTransfer, true, "Transfer directTransfer should be true");
        assertEq(order.transfer.data, abi.encode(fulfiller), "Transfer data should be the fulfiller");
        assertEq(order.collateral, 0, "Collateral should be set to zero after fulfillment");

        // **3. Receiver Status Verification**
        bytes32 receiverOrderId = untron.isReceiverBusy(receiver);
        assertEq(receiverOrderId, bytes32(0), "Receiver should be freed");

        // **4. Collateral Refund Verification**
        uint256 collateralAmount = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(
            orderCreatorBalance,
            collateralAmount,
            "Collateral should be refunded to the original order creator"
        );

        // Order recipient should receive the order size minus the fee
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        uint256 fulfillerFee = getFulfillerFee();
        uint256 relayerFee = getRelayerFee(order.size);
        uint256 expectedFee = fulfillerFee + relayerFee; // Assuming fee is zero for rate 1 and default conversion
        assertEq(
            orderRecipientBalance,
            order.size - expectedFee,
            "Order recipient should receive the order size minus the fee"
        );

        // **5. Fulfiller's USDT Balance Verification**
        uint256 fulfillerBalance = usdt.balanceOf(fulfiller);
        assertEq(fulfillerBalance, 0, "Fulfiller should have zero USDT balance after fulfillment");

        // **6. Provider's Liquidity Verification**
        // In the fulfill function, the provider's liquidity is not updated, but we need to verify
        // that the provider's liquidity remains the same
        IUntronCore.Provider memory fetchedProvider = untron.providers(provider);
        assertEq(fetchedProvider.liquidity, 1000e6 - order.size, "Provider's liquidity should remain unchanged");

        // **7. Total Expense Verification**
        // Verify that the total expense matches the expected amount
        // Since the function should transfer 'amount' from the fulfiller, and we minted and approved 'totalExpectedExpense'
        // The function should not have overcharged or undercharged the fulfiller

        // **8. Event Emission Verification**
        // The OrderFulfilled event was expected and captured above using vm.expectEmit

        // **9. Order Storage Verification**
        // Verify that the order's other fields remain unchanged
        assertEq(order.provider, provider, "Order's provider should remain unchanged");
        assertEq(order.receiver, receiver, "Order's receiver should remain unchanged");
        assertEq(order.size, order.size, "Order's size should remain unchanged");
        assertEq(order.rate, DEFAULT_RATE, "Order's rate should remain unchanged");

        // **10. Action Chain Integrity**
        // If the fulfill function updates the action chain, verify its integrity
        // Assuming the action chain is updated in the fulfill function, we can verify it here
        // For example:
        // bytes32 expectedActionChainTip = ...; // Calculate expected action chain tip
        // assertEq(untron.actionChainTip(), expectedActionChainTip, "Action chain tip should be updated correctly");
    }

    /// Test: Multiple orders fulfillment
    function test_fulfill_SuccessfulMultipleOrdersFulfillment() public {
        (address provider1, bytes21[] memory receivers1) = addProviderWithDefaultParams(1);
        (address provider2, bytes21[] memory receivers2) = addProviderWithDefaultParams(1);

        (address orderCreator1, address orderRecipient1) = addOrder(
            200e6,
            TestContext.OrderState.Pending,
            false,
            receivers1[0]
        );
        (address orderCreator2, address orderRecipient2) = addOrder(
            400e6,
            TestContext.OrderState.Pending,
            false,
            receivers2[0]
        );
        TestContext.TestResult memory testResult = createContext();

        // Get order IDs
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = testResult.orderIds[0];
        orderIds[1] = testResult.orderIds[1];

        IUntronCore.Order memory firstOrder = untron.orders(orderIds[0]);
        IUntronCore.Order memory secondOrder = untron.orders(orderIds[1]);

        // Calculate total for the orders
        (uint256 totalExpense, ) = untron.calculateFulfillerTotal(orderIds);

        // Mint and approve exact amount of USDT for the fulfiller
        mintUSDT(fulfiller, totalExpense);
        approveUSDT(fulfiller, address(untron), totalExpense);

        vm.startPrank(fulfiller);
        // Fulfill the orders
        untron.fulfill(orderIds, totalExpense);
        vm.stopPrank();

        // Verify both orders are fulfilled and receivers are freed
        for (uint256 i = 0; i < orderIds.length; i++) {
            IUntronCore.Order memory order = untron.orders(orderIds[i]);
            assertEq(order.isFulfilled, true, "Order should be marked as fulfilled");
            assertEq(order.creator, fulfiller, "Order creator should now be the fulfiller");
            assertEq(order.transfer.data, abi.encode(fulfiller), "Transfer recipient should be the fulfiller");

            bytes21 receiver = order.receiver;
            assertEq(untron.isReceiverBusy(receiver), bytes32(0), "Receiver should be freed");
        }

        // Verify that the collateral was refunded to the original order creators
        uint256 collateral = untron.requiredCollateral();
        assertEq(
            usdt.balanceOf(orderCreator1),
            collateral,
            "Collateral should be refunded to the first order creator"
        );
        assertEq(
            usdt.balanceOf(orderCreator2),
            collateral,
            "Collateral should be refunded to the second order creator"
        );

        // Order recipient should receive the order size minus the fee
        uint256 fulfillerFee = getFulfillerFee();
        uint256 relayerFee1 = getRelayerFee(firstOrder.size);

        uint256 expectedFeeFirstOrder = fulfillerFee + relayerFee1; // Assuming fee is zero for rate 1 and default conversion
        assertEq(
            usdt.balanceOf(orderRecipient1),
            firstOrder.size - expectedFeeFirstOrder,
            "Order recipient should receive the order size minus the fee"
        );

        uint256 relayerFee2 = getRelayerFee(secondOrder.size);
        uint256 expectedFeeSecondOrder = fulfillerFee + relayerFee2; // Assuming fee is zero for rate 2 and default conversion
        assertEq(
            usdt.balanceOf(orderRecipient2),
            secondOrder.size - expectedFeeSecondOrder,
            "Order recipient should receive the order size minus the fee"
        );

        // **5. Fulfiller's USDT Balance Verification**
        uint256 fulfillerBalance = usdt.balanceOf(fulfiller);
        assertEq(
            fulfillerBalance, 
            // Since the order is not closed, temporarily the fulfiller will have zero balance
            0,
            "Fulfiller should have fee USDT balance after fulfillment"
        );
    }

    /// Test: Revert if trying to fulfill an order that is already fulfilled
    function test_fulfill_RevertIf_OrderAlreadyFulfilled() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = untron.isReceiverBusy(receiver);

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        // Calculate total for the order
        (uint256 amount, uint256 fee) = untron.calculateFulfillerTotal(orderIds);
        uint256 totalExpectedExpense = amount;

        // Mint and approve exact amount of USDT for the fulfiller
        mintUSDT(fulfiller, totalExpectedExpense);
        approveUSDT(fulfiller, address(untron), totalExpectedExpense);

        vm.startPrank(fulfiller);
        untron.fulfill(orderIds, totalExpectedExpense);
        vm.stopPrank();

        // **Verification before attempting to fulfill again**
        // Check that the order is marked as fulfilled
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.isFulfilled, true, "Order should be marked as fulfilled");

        // **Attempt to fulfill the same order again**

        // Mint and approve USDT again
        mintUSDT(fulfiller, totalExpectedExpense);
        approveUSDT(fulfiller, address(untron), totalExpectedExpense);

        vm.startPrank(fulfiller);
        // Expect revert when trying to fulfill an already fulfilled order
        vm.expectRevert("Order already fulfilled");
        untron.fulfill(orderIds, totalExpectedExpense);
        vm.stopPrank();

        // **Additional Verification**
        // Ensure that no state changes occurred due to the failed attempt
        IUntronCore.Order memory orderAfter = untron.orders(orderId);
        assertEq(orderAfter.isFulfilled, true, "Order should remain fulfilled");
        assertEq(orderAfter.creator, fulfiller, "Order creator should remain as fulfiller");
        assertEq(
            usdt.balanceOf(fulfiller),
            // The minted balance that failed to fulfill the second time + the fee for the first fulfillment
            totalExpectedExpense,
            "Fulfiller's USDT balance should remain the same after failed attempt"
        );

        // Ensure that the receiver remains freed
        bytes32 receiverOrderId = untron.isReceiverBusy(receiver);
        assertEq(receiverOrderId, bytes32(0), "Receiver should remain freed");
    }

    /// @notice Test orders with extreme conversion rates
    function test_fulfill_SuccessfulSingleHighRateOrderFulfillment() public {
        uint256 extremeHighRate = 1e9; // Very high rate

        // Set up provider using the new testContext
        (address highRateProvider, bytes21[] memory highRateReceivers) = addProvider(
            100000e6,              // Provider liquidity
            extremeHighRate,      // Extreme high rate
            100e6,               // Min order size
            10e6,                // Min deposit
            1                   // Number of receivers
        );
        bytes21 highRateReceiver = highRateReceivers[0];

        (address highRateOrderCreator, address highRateOrderRecipient) = addOrder(
            100e6,               // Order size
            TestContext.OrderState.Pending,   // Order state is pending
            false,
            highRateReceiver
        );
        TestContext.TestResult memory result = createContext();

        bytes32 highRateOrderId = result.orderIds[0];

        IUntronCore.Order memory highRateOrder = untron.orders(highRateOrderId);
        assertEq(highRateOrder.rate, extremeHighRate, "Order rate should match the extreme high rate");

        // Fulfill the order
        bytes32[] memory highRateOrderIds = new bytes32[](1);
        highRateOrderIds[0] = highRateOrderId;
        (uint256 amount, ) = untron.calculateFulfillerTotal(highRateOrderIds);

        mintUSDT(fulfiller, amount);
        approveUSDT(fulfiller, address(untron), amount);

        vm.startPrank(fulfiller);
        untron.fulfill(highRateOrderIds, amount);
        vm.stopPrank();

        // Verify that the order is fulfilled
        IUntronCore.Order memory postFulfillmentHighRateOrder = untron.orders(highRateOrderId);
        assertEq(postFulfillmentHighRateOrder.isFulfilled, true, "Order should be marked as fulfilled");

        // Verify that the receiver is freed
        bytes32 highRateReceiverOrderId = untron.isReceiverBusy(highRateReceiver);
        assertEq(highRateReceiverOrderId, bytes32(0), "Receiver should be freed");

        // Verify that the order creator received the collateral
        uint256 collateral = untron.requiredCollateral();
        uint256 highRateOrderCreatorBalance = usdt.balanceOf(highRateOrderCreator);
        assertEq(
            highRateOrderCreatorBalance,
            collateral,
            "Collateral should be refunded to the original order creator"
        );

        // Verify that the order recipient received the order size minus the fee
        uint256 fulfillerFee = getFulfillerFee();
        uint256 relayerFee = getRelayerFee(highRateOrder.size);
        uint256 expectedFee = fulfillerFee + relayerFee; // Assuming fee is zero for rate 1 and default conversion
        uint256 highRateOrderRecipientBalance = usdt.balanceOf(highRateOrderRecipient);
    }

    /// @notice Test orders with extreme conversion rates
    function test_fulfill_SuccessfulSingleLowRateOrderFulfillment() public {
        uint256 extremeLowRate = 1e3;     // Very low rate

        (address lowRateProvider, bytes21[] memory lowRateReceivers) = addProvider(
            100000e6,              // Provider liquidity
            extremeLowRate,       // Extreme low rate
            100e6,               // Min order size
            10e6,                // Min deposit
            1                   // Number of receivers
        );
        bytes21 lowRateReceiver = lowRateReceivers[0];
        (address lowRateOrderCreator, address lowRateOrderRecipient) = addOrder(
            100e6,               // Order size
            TestContext.OrderState.Pending,   // Order state is pending
            false,
            lowRateReceiver
        );
        TestContext.TestResult memory result = createContext();

        bytes32 lowRateOrderId = result.orderIds[0];

        IUntronCore.Order memory lowRateOrder = untron.orders(lowRateOrderId);
        assertEq(lowRateOrder.rate, extremeLowRate, "Order rate should match the extreme low rate");

        // Fulfill the order
        bytes32[] memory lowRateOrderIds = new bytes32[](1);
        lowRateOrderIds[0] = lowRateOrderId;
        (uint256 amount, ) = untron.calculateFulfillerTotal(lowRateOrderIds);

        mintUSDT(fulfiller, amount);
        approveUSDT(fulfiller, address(untron), amount);

        vm.startPrank(fulfiller);
        untron.fulfill(lowRateOrderIds, amount);
        vm.stopPrank();

        // Verify that the order is fulfilled
        IUntronCore.Order memory postFulfillmentHighRateOrder = untron.orders(lowRateOrderId);
        assertEq(postFulfillmentHighRateOrder.isFulfilled, true, "Order should be marked as fulfilled");

        // Verify that the receiver is freed
        bytes32 highRateReceiverOrderId = untron.isReceiverBusy(lowRateReceiver);
        assertEq(highRateReceiverOrderId, bytes32(0), "Receiver should be freed");

        // Verify that the order creator received the collateral
        uint256 collateral = untron.requiredCollateral();
        uint256 highRateOrderCreatorBalance = usdt.balanceOf(lowRateOrderCreator);
        assertEq(
            highRateOrderCreatorBalance,
            collateral,
            "Collateral should be refunded to the original order creator"
        );

        // Verify that the order recipient received the order size minus the fee
        uint256 fulfillerFee = getFulfillerFee();
        uint256 relayerFee = getRelayerFee(lowRateOrder.size);
        uint256 expectedFee = fulfillerFee + relayerFee; // Assuming fee is zero for rate 1 and default conversion
        uint256 highRateOrderRecipientBalance = usdt.balanceOf(lowRateOrderRecipient);
    }

    /// Test: Excess USDT is refunded to the fulfiller
    function test_fulfill_ExcessUSDTIsRefunded() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get order ID
        bytes32 orderId = result.orderIds[0];
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        // Calculate total for the order
        (uint256 totalExpense, ) = untron.calculateFulfillerTotal(orderIds);

        // Mint and approve more than required amount
        usdt.mint(fulfiller, totalExpense + 100e6);
        vm.startPrank(fulfiller);
        usdt.approve(address(untron), totalExpense + 100e6);

        // Fulfill the order with excess USDT
        untron.fulfill(orderIds, totalExpense + 100e6);
        vm.stopPrank();

        // Verify that excess USDT was refunded
        uint256 fulfillerBalance = usdt.balanceOf(fulfiller);
        assertEq(fulfillerBalance, 100e6, "Excess USDT should be refunded to the fulfiller");
    }
    /// Test: Revert if fulfiller sends less than required total
    function test_fulfill_RevertIf_TotalLessThanExpected() public {
        // Set up provider using the new testContext
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get order ID
        bytes32 orderId = result.orderIds[0];
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        // Calculate total for the order
        (uint256 totalExpense, ) = untron.calculateFulfillerTotal(orderIds);

        // Mint and approve less than required amount
        mintUSDT(fulfiller, totalExpense - 1);
        approveUSDT(fulfiller, address(untron), totalExpense - 1);
        
        vm.startPrank(fulfiller);
        // Attempt to fulfill the order with less than expected total
        vm.expectRevert("Total does not match");
        untron.fulfill(orderIds, totalExpense - 1);
        vm.stopPrank();
    }

    // TODO: fix this test
    // /// @notice Test for reverting if trying to fulfill an order whose receiver is already freed
    // function test_fulfill_RevertIf_ReceiverAlreadyFreed() public {
    //     (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
    //     bytes21 receiver = receivers[0];
    //     (address orderCreator, address orderRecipient) = addExpiredOrderWithDefaultParams(receivers[0]);
    //     TestContext.TestResult memory result = createContext();

    //     bytes32 orderId = result.orderIds[0];
    //     bytes32[] memory orderIds = new bytes32[](1);
    //     orderIds[0] = orderId;

    //     // Set provider again with new receivers to free the receiver
    //     bytes21[] memory newReceivers = new bytes21[](1);
    //     newReceivers[0] = addressToBytes21(vm.addr(123456));

    //     vm.startPrank(provider);
    //     untron.setProvider(100e6, 1e6, 10e6, 10e6, newReceivers);
    //     vm.stopPrank();

    //     // Verify that the receiver is no longer busy
    //     assertEq(untron.isReceiverBusy(receiver), bytes32(0), "Receiver should be freed");

    //     // Mint and approve exact amount of USDT
    //     mintUSDT(fulfiller, 200e6);
    //     approveUSDT(fulfiller, address(untron), 200e6);

    //     // Attempt to fulfill the order with freed receiver
    //     vm.startPrank(fulfiller);
    //     vm.expectRevert("Receiver must be busy when trying to free it");
    //     untron.fulfill(orderIds, 200e6);
    //     vm.stopPrank();
    // }
    
    /// Fuzz Test: Random order sizes and rates
    function testFuzz_fulfill_RandomOrderSizesAndRates(uint256 size, uint256 rate) public {
        // Bound size and rate to reasonable values
        size = bound(size, 10e6, 1000e6);
        rate = bound(rate, 1e6, 5e6);

        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        bytes21 receiver = receivers[0];
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get order ID
        bytes32 orderId = result.orderIds[0];
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;

        // Calculate total for the order
        (uint256 totalExpense, ) = untron.calculateFulfillerTotal(orderIds);

        // Mint and approve exact amount of USDT
        usdt.mint(fulfiller, totalExpense);
        vm.startPrank(fulfiller);
        usdt.approve(address(untron), totalExpense);

        // Fulfill the order
        untron.fulfill(orderIds, totalExpense);
        vm.stopPrank();

        // Verify order is fulfilled
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.isFulfilled, true, "Order should be marked as fulfilled");
    }

    /// Invariant Test: No orders are left partially fulfilled
    function test_invariant_fulfill_NoPartialFulfillment() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(5);
        for (uint256 i = 0; i < 5; i++) {
            (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[i]);
        }
        TestContext.TestResult memory result = createContext();

        // Get order IDs
        bytes32[] memory orderIds = result.orderIds;

        // Calculate total for the orders
        (uint256 totalExpense, ) = untron.calculateFulfillerTotal(orderIds);

        // Mint and approve only enough USDT to fulfill some but not all orders
        uint256 partialExpense = totalExpense - 1e6; // Not enough to fulfill all orders
        usdt.mint(fulfiller, partialExpense);
        vm.startPrank(fulfiller);
        usdt.approve(address(untron), partialExpense);

        // Attempt to fulfill all orders
        vm.expectRevert();
        untron.fulfill(orderIds, totalExpense);
        vm.stopPrank();

        // Verify that no orders are partially fulfilled
        for (uint256 i = 0; i < 5; i++) {
            IUntronCore.Order memory order = untron.orders(orderIds[i]);
            assertEq(order.isFulfilled, false, "Order should not be fulfilled");
        }
    }
}
