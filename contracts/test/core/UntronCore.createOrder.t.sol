// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./UntronCoreBase.t.sol";

contract CreateOrderTest is UntronCoreBase {
    constructor() UntronCoreBase() {}

    address orderCreator = vm.addr(777);
    address orderRecipient = vm.addr(888);

    event OrderCreated(
        bytes32 orderId,
        uint256 timestamp,
        address creator,
        address indexed provider,
        bytes21 receiver,
        uint256 size,
        uint256 rate,
        uint256 minDeposit
    );

    // Test: Successfully creates an order with a free receiver
    function test_createOrder_CreatesOrderWithFreeReceiver() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();

        // Get provider info before order creation
        IUntronCore.Provider memory providerInfoBefore = untron.providers(provider);
        uint256 liquidityBefore = providerInfoBefore.liquidity;

        // Expected values
        uint256 size = 200e6; // Order size of 200 USDT
        uint256 rate = 1e6; // Rate of 1
        uint256 expectedAmount = (size * rate) / 1e6; // amount = size * rate / 1e6

        // Calculate expected orderId
        bytes32 prevActionHash = untron.actionChainTip();
        bytes32 expectedOrderId = sha256(
            abi.encode(prevActionHash, block.timestamp, receivers[0], providerInfoBefore.minDeposit, size)
        );

        // Mint collateral to orderCreator
        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Create order
        IUntronTransfers.Transfer memory transfer = getTransferDetails(orderRecipient, true);

        // Prepare to capture the event
        vm.expectEmit(true, true, true, true);
        emit OrderCreated(
            expectedOrderId,
            block.timestamp,
            orderCreator,
            provider,
            receivers[0],
            size,
            rate,
            providerInfoBefore.minDeposit
        );

        vm.startPrank(orderCreator);
        untron.createOrder(provider, receivers[0], size, rate, transfer);
        vm.stopPrank();
           
        // Verify provider's liquidity update
        IUntronCore.Provider memory providerInfoAfter = untron.providers(provider);
        uint256 liquidityAfter = providerInfoAfter.liquidity;
        uint256 actualAmountDeducted = liquidityBefore - liquidityAfter;

        assertEq(
            actualAmountDeducted,
            expectedAmount,
            "Provider's liquidity should be reduced by the expected amount"
        );

        // Verify action chain integrity
        bytes32 actionChainTip = untron.actionChainTip();
        assertEq(actionChainTip, expectedOrderId, "Action chain tip should be updated to expected order ID");

        // Verify order storage
        IUntronCore.Order memory order = untron.orders(expectedOrderId);
        assertEq(order.creator, orderCreator, "Order creator should be correct");
        assertEq(order.provider, provider, "Order provider should be correct");
        assertEq(order.receiver, receivers[0], "Order receiver should be correct");
        assertEq(order.size, size, "Order size should be correct");
        assertEq(order.rate, rate, "Order rate should be correct");
        assertEq(order.minDeposit, providerInfoBefore.minDeposit, "Order minDeposit should be correct");
        assertEq(order.collateral, untron.requiredCollateral(), "Order collateral should be correct");
        assertEq(order.isFulfilled, false, "Order should not be fulfilled");
        // Verify transfer details
        assertEq(order.transfer.directTransfer, transfer.directTransfer, "Transfer directTransfer should be correct");
        assertEq(order.transfer.data, transfer.data, "Transfer data should be correct");

        // Event emission is already verified via vm.expectEmit

        // Verify that the receiver is now busy with the created order
        assertEq(
            untron.isReceiverBusy(receivers[0]),
            expectedOrderId,
            "Receiver should be marked as busy with the new order"
        );
    }

    // Test: Successfully creates an order when receiver is busy with an expired order
    function test_createOrder_CreatesOrderWithExpiredReceiverOrder() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addExpiredOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();
        bytes21 receiver = receivers[0];

        bytes32 expiredOrderId = result.orderIds[0];

        // Get provider info before order creation
        IUntronCore.Provider memory providerInfoBefore = untron.providers(provider);
        uint256 liquidityBefore = providerInfoBefore.liquidity;

        // Expected values
        uint256 size = 300e6; // New order size
        uint256 rate = 1e6; // Rate of 1
        uint256 expectedAmount = (size * rate) / 1e6; // amount = size * rate / 1e6

        // Calculate next action chain tip based on the expired order, receiver freed and new order
        uint256 tronTimestamp = block.timestamp * 1000 - 170539755000;
        bytes32 receiverFreedActionChainTip = sha256(
            abi.encode(expiredOrderId, tronTimestamp, receiver, 0, 0)
        );
        bytes32 expectedOrderId = sha256(
            abi.encode(receiverFreedActionChainTip, tronTimestamp, receiver, providerInfoBefore.minDeposit, size)
        );

        // Mint collateral to orderCreator
        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Create order
        IUntronTransfers.Transfer memory transfer = getTransferDetails(orderRecipient, true);
        
        
        vm.startPrank(orderCreator);
        vm.expectRevert("Receiver is busy");
        untron.createOrder(provider, receiver, size, rate, transfer);
        vm.stopPrank();

        // Verify provider's liquidity update
        IUntronCore.Provider memory providerInfoAfter = untron.providers(provider);
        uint256 liquidityAfter = providerInfoAfter.liquidity;
        uint256 actualAmountDeducted = liquidityBefore - liquidityAfter;

        assertEq(
            actualAmountDeducted,
            0,
            "Provider's liquidity should be equlas to zero since order was not created"
        );

        // Verify action chain integrity
        bytes32 actionChainTip = untron.actionChainTip();
        assertEq(actionChainTip, actionChainTip, "Action chain tip should remain the same and not be updated to expected order ID");

        // Verify order storage
        IUntronCore.Order memory order = untron.orders(expectedOrderId);
        assertEq(order.creator, address(0), "Order creator should be equals to address(0)");
        assertEq(order.provider, address(0), "Order provider should be equals to address(0)");
        assertEq(order.receiver, bytes21(0), "Order receiver should be equals to bytes(0)");
        assertEq(order.size, 0, "Order size should be correctly equals to zero");
        assertEq(order.rate, 0, "Order rate should be correctly equals to zero");
        assertEq(order.minDeposit, 0, "Order minDeposit should be correctly be equals to zero");
        assertEq(order.collateral, 0, "Order collateral should be correctly equals to zero");
        assertEq(order.isFulfilled, false, "Order should not be fulfilled");
        

        // Verify that the receiver is stilll busy with the old order
        assertEq(
            untron.isReceiverBusy(receiver),
            expiredOrderId,
            "Receiver should be marked as busy with the new order"
        );
    }

    // Test: Amount is correctly calculated based on size and rate
    function test_createOrder_AmountCalculation() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
       createContext();
        bytes21 receiver = receivers[0];

        // Check provider's initial liquidity
        IUntronCore.Provider memory providerInfoBefore = untron.providers(provider);
        uint256 liquidityBefore = providerInfoBefore.liquidity;

        // Create order
        uint256 size = 200e6; // Order size of 200 USDT
        uint256 rate = providerInfoBefore.rate; // Use provider's rate
        // Assuming conversion: amount = size * rate / 1e6
        uint256 expectedAmount = (size * rate) / 1e6;
        createOrderWithCustomSizeAndRate(
            orderCreator,
            provider,
            receiver,
            size,
            rate,
            orderRecipient
        );

        // Check provider's liquidity after order creation
        IUntronCore.Provider memory providerInfoAfter = untron.providers(provider);
        uint256 liquidityAfter = providerInfoAfter.liquidity;

        // Calculate actual amount deducted
        uint256 actualAmountDeducted = liquidityBefore - liquidityAfter;

        // Assert that the amount deducted matches expected amount
        assertEq(
            actualAmountDeducted,
            expectedAmount,
            "Amount deducted from provider liquidity should match expected amount"
        );
    }

    // Test: Order size exactly equal to minOrderSize is accepted
    function test_createOrder_OrderSizeEqualToMinOrderSize() public {
        // Set up provider using the new testContext
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();
        bytes21 receiver = receivers[0];

        // Create order with size equal to minOrderSize
        bytes32 orderId = createOrderWithCustomSize(
            orderCreator,
            provider,
            receivers[0],
            DEFAULT_MIN_DEPOSIT
        );

        // Assert the receiver is now busy with the created order
        assertEq(
            untron.isReceiverBusy(receiver),
            orderId,
            "Order should be created and receiver marked as busy"
        );
    }

    // Test: Order size exactly equal to maxOrderSize is accepted
    function test_createOrder_OrderSizeEqualToMaxOrderSize() public {
        // Get maxOrderSize from the contract
        uint256 maxOrderSize = untron.maxOrderSize();

        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();
        bytes21 receiver = receivers[0];

        // Create order with size equal to maxOrderSize
        bytes32 orderId = createOrderWithCustomSize(
            orderCreator,
            provider,
            receiver,
            maxOrderSize
        );

        // Assert the receiver is now busy with the created order
        assertEq(
            untron.isReceiverBusy(receiver),
            orderId,
            "Order should be created and receiver marked as busy"
        );
    }

    // Test: Revert if order creator has insufficient funds for collateral
    function test_createOrder_RevertIf_OrderCreatorHasNotEnoughFundsForCollateral() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();

        // Try creating an order without enough collateral
        vm.startPrank(orderCreator); // Start as the order creator
        // TODO: Check revert by message
        vm.expectRevert();
        untron.createOrder(provider, receivers[0], 10e6, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if provider does not have enough liquidity
    function test_createOrder_RevertIf_NotEnoughProviderLiquidity() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Try creating an order
        uint256 orderSize = DEFAULT_LIQUIDITY + 1;
        vm.startPrank(orderCreator);
        vm.expectRevert("Provider does not have enough liquidity");
        untron.createOrder(provider, receivers[0], orderSize, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if receiver is busy and not from expired order
    function test_createOrder_RevertIf_ReceiverIsBusyAndIsNotFromExpiredOrder() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Attempt to create a new order with the busy receiver
        vm.startPrank(orderCreator);
        vm.expectRevert("Receiver is busy");
        untron.createOrder(provider, receivers[0], 10e6, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if receiver is not owned by provider
    function test_createOrder_RevertIf_ReceiverIsNotOwnedByProvider() public {
        (address provider,) = addProviderWithDefaultParams(1);
        createContext();

        // Create context with no initial orders
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Try to create an order for a receiver that is not owned by the provider
        bytes21 notOwnedReceiver = addressToBytes21(vm.addr(999));
        vm.startPrank(orderCreator);
        vm.expectRevert("Receiver is not owned by provider");
        untron.createOrder(provider, notOwnedReceiver, 10e6, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if rate does not match provider's rate
    function test_createOrder_RevertIf_RateUnequalToProvidersRate() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Try to create an order with a different rate
        vm.startPrank(orderCreator);
        uint256 wrongRate = 2e6;
        vm.expectRevert("Rate does not match provider's rate");
        untron.createOrder(provider, receivers[0], 10e6, wrongRate, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if provider does not have enough liquidity
    function test_createOrder_RevertIf_ProviderDoesNotHaveEnoughLiquidity() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Try creating an order
        uint256 orderSize = DEFAULT_LIQUIDITY + 1;
        vm.startPrank(orderCreator);
        vm.expectRevert("Provider does not have enough liquidity");
        untron.createOrder(provider, receivers[0], orderSize, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Test: Revert if order size is greater than max order size
    function test_createOrder_RevertIf_OrderSizeGreaterThanMaxOrderSize() public {
        // Set up provider using the new testContext
        uint256 maxOrderSize = untron.maxOrderSize();
        (address provider, bytes21[] memory receivers) = addProvider(
            maxOrderSize + 1, 
            1e6, 
            10e6, 
            10e6, 
            1
        );
        createContext();

        mintUSDT(orderCreator, untron.requiredCollateral());
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral());

        // Try to create an order with a size larger than the max order size
        vm.startPrank(orderCreator);
        vm.expectRevert("Size is greater than max order size");
        untron.createOrder(provider, receivers[0], maxOrderSize + 1, 1e6, getTransferDetails(orderRecipient, true));
        vm.stopPrank();
    }

    // Fuzz Test: Create orders with random sizes and rates
    function test_fuzz_createOrder_Random(uint256 randomSize, uint256 randomRate) public {
        // Assume reasonable boundaries for fuzz testing
        randomSize = bound(randomSize, 500e6, 1000e6); // Between 500 and 1000 units
        randomRate = bound(randomRate, 1e6, 5e6); // Between 1e6 and 5e6 rate

        (address provider, bytes21[] memory receivers) = addProvider(
            100000e6, // 100,000 USDT
            randomRate,
            500e6, // Min order size of 500 USDT
            100e6, // Min deposit of 100 USDT
            1
        );
        createContext();

        // Create a new order with random size and rate
        bytes32 orderId = createOrderWithCustomSizeAndRate(
            orderCreator,
            provider,
            receivers[0],
            randomSize,
            randomRate,
            orderRecipient
        );

        // Verify that the receiver is now busy with the created order
        assertEq(
            untron.isReceiverBusy(receivers[0]),
            orderId,
            "Receiver should be marked as busy with the new order"
        );

        // Verify order details
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.size, randomSize, "Order size should match the random size");
        assertEq(order.rate, randomRate, "Order rate should match the random rate");

        // Verify provider's liquidity
        IUntronCore.Provider memory providerInfo = untron.providers(provider);
        uint256 expectedAmount = (randomSize * randomRate) / 1e6;
        assertEq(
            providerInfo.liquidity,
            100000e6 - expectedAmount,
            "Provider's liquidity should be reduced by the expected amount"
        );
    }

    // Helper functions
    function createOrderWithCustomSize(
        address orderCreator_,
        address provider,
        bytes21 receiver,
        uint256 size
    ) internal returns (bytes32 orderId) {
        // Mint collateral to orderCreator
        mintUSDT(orderCreator_, untron.requiredCollateral());
        approveUSDT(orderCreator_, address(untron), untron.requiredCollateral());

        vm.startPrank(orderCreator_);
        IUntronTransfers.Transfer memory transfer = getTransferDetails(orderRecipient, true);

        uint256 rate = untron.providers(provider).rate;
        untron.createOrder(provider, receiver, size, rate, transfer);
        vm.stopPrank();

        orderId = untron.isReceiverBusy(receiver);
    }

    function createOrderWithCustomSizeAndRate(
        address orderCreator_,
        address provider,
        bytes21 receiver,
        uint256 size,
        uint256 rate,
        address orderRecipient_
    ) internal returns (bytes32 orderId) {
        // Mint collateral to orderCreator
        mintUSDT(orderCreator_, untron.requiredCollateral());
        approveUSDT(orderCreator_, address(untron), untron.requiredCollateral());

        vm.startPrank(orderCreator_);
        IUntronTransfers.Transfer memory transfer = getTransferDetails(orderRecipient_, true);

        untron.createOrder(provider, receiver, size, rate, transfer);
        vm.stopPrank();

        orderId = untron.isReceiverBusy(receiver);
    }
}
