// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../common/TestContext.sol";
import "./UntronCoreBase.t.sol";

contract CloseOrdersTest is UntronCoreBase {
    event OrderClosed(bytes32 indexed orderId, address relayer);
    event RelayUpdated(address relayer, bytes32 stateHash);
    event OrderFulfilled(bytes32 indexed orderId, address fulfiller);

    constructor() UntronCoreBase() {}

    function test_closeOrders_SuccessfulSinglePendingOrderClosure() public {
        // Given
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory createdOrder = getOrderFromContext(orderId);

        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed order inflow is equal to order size
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: createdOrder.size });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Capture events
        vm.expectEmit();
        emit OrderClosed(orderId, address(this));
        vm.expectEmit();
        emit RelayUpdated(address(this), newStateHash);

        // When
        untron.closeOrders(proof, publicValues);

        // Then
        // Verify that the order is deleted
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // Verify that provider's liquidity is updated
        IUntronCore.Provider memory createdProvider = untron.providers(provider);
        uint256 expectedRemainingLiquidity = 1000e6 - createdOrder.size; // Since inflow equals order size
        assertEq(createdProvider.liquidity, expectedRemainingLiquidity, "Provider liquidity should be updated");

        // Verify that the state hash is updated
        assertEq(untron.stateHash(), newStateHash, "State hash should be updated");

        // Verify that total fee is transferred to the protocol owner
        uint256 ownerBalance = usdt.balanceOf(untron.owner());
        uint256 expectedFee = getRelayerFee(createdOrder.size) + getFulfillerFee();
        assertEq(ownerBalance, expectedFee, "Protocol owner should receive the total fee");

        // Here order recipient and order creator are the same, thus we check everything at once
        // Verify that the order recipient received the correct amount
        uint256 collateral = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(orderCreatorBalance, collateral, "Order creator should receive the correct amount");

        // Verify that the order recipient received the correct amount
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        uint256 expectedAmount = createdOrder.size - expectedFee; // Since rate is 1 and inflow equals order size
        assertEq(orderRecipientBalance, expectedAmount, "Order recipient should receive the correct amount");

    }

    function test_closeOrders_SuccessfulSingleFulfilledOrderClosure() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient, address fulfiller) = addFulfilledOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory createdOrder = getOrderFromContext(orderId);

        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed order inflow is equal to order size
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: createdOrder.size });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Capture events
        vm.expectEmit();
        emit OrderClosed(orderId, address(this));
        vm.expectEmit();
        emit RelayUpdated(address(this), newStateHash);

        // When
        untron.closeOrders(proof, publicValues);

        // Then
        // Verify that the order is deleted
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");
    
        // Verify that provider's liquidity is updated
        IUntronCore.Provider memory createdProvider = untron.providers(provider);
        uint256 expectedRemainingLiquidity = DEFAULT_LIQUIDITY - createdOrder.size; // Since inflow equals order size
        assertEq(createdProvider.liquidity, expectedRemainingLiquidity, "Provider liquidity should be updated");

        // Verify that the state hash is updated
        assertEq(untron.stateHash(), newStateHash, "State hash should be updated");

        // Verify that total fee is transferred to the protocol owner
        uint256 ownerBalance = usdt.balanceOf(untron.owner());
        uint256 expectedFee = getRelayerFee(createdOrder.size);
        assertEq(ownerBalance, expectedFee, "Protocol owner should receive the total fee");

        // Verify that the order recipient received the correct amount
        uint256 expectedAmount = createdOrder.size - (expectedFee + getFulfillerFee()); // Since rate is 1 and inflow equals order size
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        assertEq(orderRecipientBalance, expectedAmount, "Order recipient should receive the correct amount");

        // Verify that the fulfiller received the correct amount
        uint256 fulfillerBalance = usdt.balanceOf(fulfiller);
        assertEq(fulfillerBalance, expectedAmount + getFulfillerFee(), "Fulfiller should receive the correct amount");

        // Verify that the order creator received the collateral refund
        uint256 collateral = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(orderCreatorBalance, collateral, "Order creator should receive the collateral refund");
    }
    
    function test_closeOrders_SuccessfulSingleExpiredUnfulfilledOrderClosure() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient) = addExpiredOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory createdOrder = getOrderFromContext(orderId);

        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: createdOrder.size });

        bytes memory publicValues = abi.encode(
            oldStateHash,
            newStateHash,
            latestIncludedAction,
            closedOrders
        );
        bytes memory proof = ""; // Mocked proof

        // **Capture Events**
        vm.expectEmit();
        emit OrderClosed(orderId, address(this));
        vm.expectEmit();
        emit RelayUpdated(address(this), newStateHash);

        // **Call closeOrders**
        untron.closeOrders(proof, publicValues);

        // **Verifications:**

        // 1. **Order is Deleted**
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // 2. **Provider's Liquidity is Correct**
        IUntronCore.Provider memory providerData = untron.providers(provider);
        assertEq(
            providerData.liquidity,
            1000e6 - createdOrder.size,
            "Provider's liquidity should be reduced by the order size"
        );

        // 3. **Receiver is Freed**
        bytes32 busyOrderId = untron.isReceiverBusy(receivers[0]);
        assertEq(
            busyOrderId,
            bytes32(0),
            "Receiver should be freed after closing expired order"
        );

        // 4. **Contract's USDT Balance Reflects Liquidity Minus Fulfilled Amount**
        uint256 contractBalance = usdt.balanceOf(address(untron));
        assertEq(
            contractBalance,
            1000e6 - createdOrder.size,
            "Contract's USDT balance should match provider's liquidity"
        );

        // 5. **Collateral is Refunded to Order Creator**
        uint256 collateralAmount = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(
            orderCreatorBalance,
            collateralAmount,
            "Collateral should be refunded to the order creator"
        );

        // 6. **Protocol Owner Fee**
        uint256 protocolOwnerBalance = usdt.balanceOf(untron.owner());
        uint256 expectedFee = getRelayerFee(createdOrder.size) + getFulfillerFee();
        assertEq(
            protocolOwnerBalance,
            expectedFee,
            "Protocol owner should receive the total fee"
        );

        // 7. **State Hash is Updated**
        assertEq(
            untron.stateHash(),
            newStateHash,
            "State hash should be updated"
        );

        // 8. **Order Recipient Balance**
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        uint256 expectedAmount = createdOrder.size - expectedFee; // Since rate is 1 and inflow equals order size
        assertEq(
            orderRecipientBalance,
            expectedAmount,
            "Order recipient should receive the correct amount"
        );

        // 9. **Fulfiller Balance**
        uint256 fulfillerBalance = usdt.balanceOf(contextFulfiller);
        assertEq(
            fulfillerBalance,
            0,
            "Fulfiller should not receive any funds"
        );
    }

    function test_closeOrders_SuccesfulSingleExpiredFulfilledOrderClosure() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient, address fulfiller) = addFulfilledOrderWithDefaultParams(receivers[0]);
        expireOrder();
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory createdOrder = getOrderFromContext(orderId);

        // **Prepare publicValues for closeOrders**
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: createdOrder.size });

        bytes memory publicValues = abi.encode(
            oldStateHash,
            newStateHash,
            latestIncludedAction,
            closedOrders
        );
        bytes memory proof = ""; // Mocked proof

        // **Mock the ZK Proof Verification**
        // Assuming verifyProof always succeeds in tests.

        // **Capture Events**
        vm.expectEmit();
        emit OrderClosed(orderId, address(this));
        vm.expectEmit();
        emit RelayUpdated(address(this), newStateHash);

        // **Call closeOrders**
        untron.closeOrders(proof, publicValues);

        // **Verifications:**

        // 1. **Order is Deleted**
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // 2. **Collateral is Refunded to Order Creator**
        uint256 collateralAmount = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(
            orderCreatorBalance,
            collateralAmount,
            "Collateral should be refunded to the order creator"
        );

        // 2b. **Balance is sent to Order Recipient (on fulfillment)**
        uint256 relayerFee = getRelayerFee(createdOrder.size);
        uint256 fulfillerFee = getFulfillerFee();
        uint256 expectedFee = fulfillerFee + relayerFee; // Assuming fee is zero for rate 1 and default conversion
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        assertEq(
            orderRecipientBalance,
            createdOrder.size - expectedFee,
            "Order recipient should receive the remaining balance"
        );

        // 2c. **Fulfiller fee and order funds are sent to fulfiller**
        uint256 fulfillerBalance = usdt.balanceOf(fulfiller);
        assertEq(
            fulfillerBalance,
            createdOrder.size - expectedFee + fulfillerFee,
            "Fulfiller should receive the fee"
        );

        // 3. **Receiver is Freed**
        bytes32 busyOrderId = untron.isReceiverBusy(receivers[0]);
        assertEq(
            busyOrderId,
            bytes32(0),
            "Receiver should be freed after closing fulfilled order"
        );

        // 4. **Contract's USDT Balance Reflects Liquidity Minus Fulfilled Amount**
        uint256 initialLiquidity = 1000e6;
        uint256 expectedContractBalance = initialLiquidity - createdOrder.size;
        uint256 contractBalance = usdt.balanceOf(address(untron));
        assertEq(
            contractBalance,
            expectedContractBalance,
            "Contract's USDT balance should match provider's liquidity minus fulfilled amount"
        );

        // 5. **Provider's Liquidity is Correct**
        IUntronCore.Provider memory providerData = untron.providers(provider);
        assertEq(
            providerData.liquidity,
            expectedContractBalance,
            "Provider's liquidity should be reduced by the fulfilled amount"
        );
    }

    function test_closeOrders_SuccessfulMultipleOrdersClosure() public {
        (address provider1, bytes21[] memory receivers1) = addProviderWithDefaultParams(1);
        (address provider2, bytes21[] memory receivers2) = addProviderWithDefaultParams(2);

        (address orderCreator1, address orderRecipient1) = addOrderWithDefaultParams(receivers1[0]);
        (address orderCreator2, address orderRecipient2,) = addFulfilledOrderWithDefaultParams(receivers2[0]);

        // Create context
        TestContext.TestResult memory result = createContext();

        // Get order IDs
        bytes32 orderId1 = result.orderIds[0];
        bytes32 orderId2 = result.orderIds[1];

        // Prepare public values
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed orders
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](2);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId1, inflow: 5e6 }); // Partial inflow
        closedOrders[1] = IUntronCore.Inflow({ order: orderId2, inflow: 10e6 }); // Full inflow

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Call closeOrders
        untron.closeOrders(proof, publicValues);

        // Verify orders are deleted
        IUntronCore.Order memory order1 = untron.orders(orderId1);
        IUntronCore.Order memory order2 = untron.orders(orderId2);
        assertEq(order1.creator, address(0), "Order 1 should be deleted");
        assertEq(order2.creator, address(0), "Order 2 should be deleted");

        // Verify provider liquidity updates
        UntronCore.Provider memory obtainedProvider1 = untron.providers(provider1);
        UntronCore.Provider memory obtainedProvider2 = untron.providers(provider2);

        // Calculate expected remaining liquidity for provider 1
        uint256 amount1 = (5e6 * obtainedProvider1.rate) / 1e6;
        uint256 remainingLiquidity1 = obtainedProvider1.liquidity;
        uint256 expectedRemainingLiquidity1 = DEFAULT_LIQUIDITY - amount1;
        assertEq(
            remainingLiquidity1,
            expectedRemainingLiquidity1,
            "Provider 1 liquidity should be updated correctly"
        );

        // Provider 2, inflow equals order size
        uint256 amount2 = (10e6 * obtainedProvider2.rate) / 1e6;
        uint256 remainingLiquidity2 = obtainedProvider2.liquidity;
        uint256 expectedRemainingLiquidity2 = DEFAULT_LIQUIDITY - amount2;
        assertEq(
            remainingLiquidity2,
            expectedRemainingLiquidity2,
            "Provider 2 liquidity should be updated correctly"
        );

        uint256 fulfillerFee = getFulfillerFee();

        // Verify order recipients received collateral refunds
        uint256 orderRecipient1Balance = usdt.balanceOf(orderRecipient1);
        uint256 relayerFee = getRelayerFee(5e6);
        uint256 expectedAmount1 = 5e6; // Since rate is 1 and inflow is 5e6
        uint256 expectedFee1 = fulfillerFee + relayerFee;
        assertEq(orderRecipient1Balance, expectedAmount1 - expectedFee1, "Order recipient 1 should receive correct amount");

        uint256 orderRecipient2Balance = usdt.balanceOf(orderRecipient2);
        uint256 expectedAmount2 = (10e6 * obtainedProvider2.rate) / 1e6; // Since rate is 1 and inflow is 10e6
        uint256 relayerFee2 = getRelayerFee(expectedAmount2);
        uint256 expectedFee2 = fulfillerFee + relayerFee2; // Assuming fee is zero for rate 2 and default conversion
        assertEq(orderRecipient2Balance, expectedAmount2 - expectedFee2, "Order recipient 2 should receive correct amount");

        // Verify collateral handling for order creators
        uint256 collateral1 = untron.requiredCollateral();
        uint256 collateral2 = untron.requiredCollateral();
        assertEq(usdt.balanceOf(orderCreator1), collateral1, "Order creator 1 should receive total collateral");
        assertEq(usdt.balanceOf(orderCreator2), collateral2, "Order creator 2 should receive total collateral");

        // Verify protocol owner fee
        uint256 protocolOwnerBalance = usdt.balanceOf(untron.owner());
        uint256 expectedProtocolBalance = expectedFee1 + expectedFee2 - fulfillerFee;
        assertEq(protocolOwnerBalance, expectedProtocolBalance, "Protocol owner should receive total fee");
    }

    function test_closeOrders_SuccesfulSinglePendingOrderClosureWithZeroInflow() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator,) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];

        // Prepare public values
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed order inflow is zero
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: 0});

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Call closeOrders
        untron.closeOrders(proof, publicValues);

        // Verify that the order is deleted
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // Verify that provider's liquidity is unchanged
        IUntronCore.Provider memory fetchedProvider = untron.providers(provider);
        assertEq(fetchedProvider.liquidity, 1000e6, "Provider liquidity should remain unchanged");

        // Verify that collateral is slashed and sent to the protocol owner
        uint256 collateral = untron.requiredCollateral();
        uint256 protocolOwnerBalance = usdt.balanceOf(untron.owner());
        assertEq(protocolOwnerBalance, collateral, "Collateral should be slashed and sent to protocol owner");
        // Check that order creator has no balance
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(orderCreatorBalance, 0, "Order creator should have no balance");

        // Verify that the state hash is updated
        assertEq(untron.stateHash(), newStateHash, "State hash should be updated");
    }

    function test_closeOrders_SuccessfulSinglePendingOrderClosureWithPartialInflow() public {
        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get the order ID
        bytes32 orderId = result.orderIds[0];

        // Prepare public values
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed order inflow is less than the order size
        uint256 partialInflow = 5e6; // 50% of default order size
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({order: orderId, inflow: partialInflow});

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Call closeOrders
        untron.closeOrders(proof, publicValues);

        // Verify that the order is deleted
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // Verify provider's liquidity update
        IUntronCore.Provider memory fetchedProvider = untron.providers(provider);
        uint256 expectedRemainingLiquidity = 1000e6 - partialInflow; // Since inflow is 50% of order size
        assertEq(fetchedProvider.liquidity, expectedRemainingLiquidity, "Provider liquidity should be updated correctly");

        // Verify that the order recipient received the partial amount
        uint256 relayerFee = getRelayerFee(partialInflow);
        uint256 fulfillerFee = getFulfillerFee();
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        assertEq(orderRecipientBalance, partialInflow - relayerFee - fulfillerFee, "Order recipient should receive the partial inflow amount minus fees");

        // Verify that collateral is refunded to the order creator
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        uint256 collateral = untron.requiredCollateral();
        assertEq(orderCreatorBalance, collateral, "Order creator should receive collateral refund");

        // Verify that the state hash is updated
        assertEq(untron.stateHash(), newStateHash, "State hash should be updated");
    }

    function test_closeOrders_SuccessfulSinglePendingOrderClosureWithCustomParams() public {
        // Given
        (address provider, bytes21[] memory receivers) = addProvider(
            134e6, // Liquidity
            2.14e6, // Rate
            10e6, // Min order size
            10e6, // Min deposit
            1 // Number of receivers
        );
        (address orderCreator, address orderRecipient) = addOrder(
            44e6,
            TestContext.OrderState.Pending,
            false,
            receivers[0]
        );
        TestContext.TestResult memory result = createContext();

        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory createdOrder = getOrderFromContext(orderId);

        // Prepare public values
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Closed order inflow is equal to order size
        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: createdOrder.size });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Capture events
        vm.expectEmit();
        emit OrderClosed(orderId, address(this));
        vm.expectEmit();
        emit RelayUpdated(address(this), newStateHash);

        // When
        untron.closeOrders(proof, publicValues);

        // Then
        // Verify that the order is deleted
        IUntronCore.Order memory order = untron.orders(orderId);
        assertEq(order.creator, address(0), "Order should be deleted");

        // Verify that provider's liquidity is updated
        IUntronCore.Provider memory createdProvider = untron.providers(provider);
        uint256 expectedRemainingLiquidity = 134e6 - (createdOrder.size * 2.14e6 / 1e6); // Since inflow equals order size
        assertEq(createdProvider.liquidity, expectedRemainingLiquidity, "Provider liquidity should be updated");

        // Verify that the state hash is updated
        assertEq(untron.stateHash(), newStateHash, "State hash should be updated");

        // Verify that total fee is transferred to the protocol owner
        uint256 ownerBalance = usdt.balanceOf(untron.owner());
        uint256 expectedFee = getRelayerFee(createdOrder.size * 2.14e6 / 1e6)
            + getFulfillerFee();
        assertEq(ownerBalance, expectedFee, "Protocol owner should receive the total fee");

        // Here order recipient and order creator are the same, thus we check everything at once
        // Verify that the order recipient received the correct amount
        uint256 collateral = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(orderCreatorBalance, collateral, "Order creator should receive the correct amount");

        // Verify that the order recipient received the correct amount
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        uint256 expectedAmount = (createdOrder.size * 2.14e6 / 1e6) - expectedFee; // Since rate is 2.14 and inflow equals order size
        assertEq(orderRecipientBalance, expectedAmount, "Order recipient should receive the correct amount");
    }

    function test_closeOrders_RevertIf_InvalidOldStateHash() public {
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get the order ID
        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory order = getOrderFromContext(orderId);

        // Prepare public values with incorrect old state hash
        bytes32 oldStateHash = keccak256("invalid_state_hash");
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: order.size });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Expect revert
        vm.expectRevert("Old state hash is invalid");
        untron.closeOrders(proof, publicValues);
    }

    function test_closeOrders_RevertIf_InvalidLatestIncludedAction() public {
        (, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get the order ID
        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory order = getOrderFromContext(orderId);

        // Prepare public values with invalid latestIncludedAction
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = bytes32("invalid_action"); // Invalid action

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: order.size });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Expect revert
        vm.expectRevert("Latest included action is invalid");
        untron.closeOrders(proof, publicValues);
    }

    // Fuzz Test: Random inflows and order sizes
    function testFuzz_closeOrders_RandomInflows(uint256 inflow) public {
        // Bound inflow to reasonable values
        inflow = bound(inflow, 10e6, 1000e6);

        (address provider, bytes21[] memory receivers) = addProviderWithDefaultParams(1);
        (address orderCreator, address orderRecipient) = addOrderWithDefaultParams(receivers[0]);
        TestContext.TestResult memory result = createContext();

        // Get the order ID
        bytes32 orderId = result.orderIds[0];
        IUntronCore.Order memory order = getOrderFromContext(orderId);

        // Prepare public values
        bytes32 oldStateHash = untron.stateHash();
        bytes32 newStateHash = keccak256(abi.encodePacked(oldStateHash, "new_state"));
        bytes32 latestIncludedAction = untron.actionChainTip();

        // Ensure inflow does not exceed order size
        uint256 adjustedInflow = inflow > order.size ? order.size : inflow;

        IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
        closedOrders[0] = IUntronCore.Inflow({ order: orderId, inflow: adjustedInflow });

        bytes memory publicValues = abi.encode(oldStateHash, newStateHash, latestIncludedAction, closedOrders);
        bytes memory proof = ""; // Assuming proof verification is mocked

        // Call closeOrders
        untron.closeOrders(proof, publicValues);
        // Verify that the order is deleted
        IUntronCore.Order memory deletedOrder = untron.orders(orderId);
        assertEq(deletedOrder.creator, address(0), "Order should be deleted");

        // Verify that provider's liquidity is updated correctly
        IUntronCore.Provider memory fetchedProvider = untron.providers(provider);
        uint256 expectedLiquidityReduction = (adjustedInflow * 1e6) / 1e6; // Default rate is 1
        uint256 expectedRemainingLiquidity = DEFAULT_LIQUIDITY - expectedLiquidityReduction;
        assertEq(fetchedProvider.liquidity, expectedRemainingLiquidity, "Provider liquidity should be updated correctly");

        // Verify that the order recipient received the correct amount
        uint256 expectedAmount = adjustedInflow - getRelayerFee(adjustedInflow) - getFulfillerFee();
        uint256 orderRecipientBalance = usdt.balanceOf(orderRecipient);
        assertEq(orderRecipientBalance, expectedAmount, "Order recipient should receive the correct amount");

        // Verify that the order creator received the collateral refund
        uint256 collateral = untron.requiredCollateral();
        uint256 orderCreatorBalance = usdt.balanceOf(orderCreator);
        assertEq(orderCreatorBalance, collateral, "Order creator should receive the collateral refund");
    }
}
