// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "../mocks/MockUSDT.sol";
import "../mocks/MockLifi.sol";
import "@sp1-contracts/SP1MockVerifier.sol";
import "./UntronCoreUtils.sol";
import "../../src/interfaces/IUntronCore.sol";

// TODO: 
// 1. Support sequence of actions, (e.g addProvider then addOrder then addProvider), create the context in the order they are called
abstract contract TestContext is UntronCoreUtils {
    // Constructor
    constructor() UntronCoreUtils() {}
    
    // Constants
    uint256 public constant DEFAULT_LIQUIDITY = 1000e6;
    uint256 public constant DEFAULT_RATE = 1e6;
    uint256 public constant DEFAULT_MIN_ORDER_SIZE = 10e6;
    uint256 public constant DEFAULT_MIN_DEPOSIT = 10e6;
    uint256 public constant DEFAULT_ORDER_SIZE = 10e6;
    OrderState public constant DEFAULT_ORDER_STATE = OrderState.Pending;
    bool public constant DEFAULT_WAS_FULFILLED_BEFORE_CLOSING = false;

    // Default values. If more than one is created we offset by 1 each time
    address public constant DEFAULT_ORDER_CREATOR = address(111);
    address public constant DEFAULT_ORDER_RECIPIENT = address(222);
    address public constant DEFAULT_ORDER_FULFILLER = address(333);
    address public constant DEFAULT_PROVIDER = address(444);
    address public constant DEFAULT_RECEIVER = address(555);

    // Current values (incremented after each use)
    address public contextOrderCreator = DEFAULT_ORDER_CREATOR;
    address public contextOrderRecipient = DEFAULT_ORDER_RECIPIENT;
    address public contextFulfiller = DEFAULT_ORDER_FULFILLER;
    address public contextProvider = DEFAULT_PROVIDER;
    bytes21 public contextReceiver; // Setup after untronCoreUtils is initialized

    // Store current context (after createContext is called)
    mapping(address => IUntronCore.Provider) public providers;
    mapping(bytes32 => IUntronCore.Order) public orders;

    // Mapping to get provider by receiver (before createContext is called)
    mapping(bytes21 => address) public providerByReceiver;

    function getProviderFromContext(address _provider) public view returns (IUntronCore.Provider memory) {
        return providers[_provider];
    }

    function getProviderByReceiverFromContext(bytes21 _receiver) public view returns (address) {
        return providerByReceiver[_receiver];
    }

    function getOrderFromContext(bytes32 orderId) public view returns (IUntronCore.Order memory) {
        return orders[orderId];
    }

    struct TestParams {
        ProviderParams[] providers;
        OrderParams[] orders;
    }

    struct ProviderParams {
        address provider;
        uint256 liquidity;
        uint256 rate;
        uint256 minOrderSize;
        uint256 minDeposit;
        bytes21[] receivers;
    }

    struct OrderParams {
        address orderCreator;
        address provider;
        bytes21 receiver;
        uint256 size;
        // State flags
        OrderState state;                // Enum to define the state of the order
        bool wasFulfilledBeforeClosing; // For closed orders
        // If not specified then recipient will be the order creator
        address recipient;
        // If not specified then there is no fulfiller
        address fulfiller;
    }

    struct TestResult {
        address[] providers;
        bytes32[] orderIds;
    }

    // Enum to define the various order states
    enum OrderState {
        Pending,   // Order is created but no further action
        Fulfilled, // Order has been fulfilled
        Expired,   // Order has expired
        Stopped,   // Order has been stopped
        Closed     // Order has been closed
    }
    
    TestParams testParams;

    function get() external view returns(TestParams memory) {
        return testParams;
    }

    function contextSetup() public {
        console.log("Setting up test context");
        contextReceiver = addressToBytes21(DEFAULT_RECEIVER);
    }

    function incrementOrderCreator() public {
        contextOrderCreator = address(uint160(addressToUint256(contextOrderCreator) + 1));
    }
    function incrementOrderRecipient() public {
        contextOrderRecipient = address(uint160(addressToUint256(contextOrderRecipient) + 1));
    }
    function incrementFulfiller() public {
        contextFulfiller = address(uint160(addressToUint256(contextFulfiller) + 1));
    }
    function incrementProvider() public {
        contextProvider = address(uint160(addressToUint256(contextProvider) + 1));
    }
    function incrementReceiver() public {
        contextReceiver = addressToBytes21(
            address(uint160(bytes21ToAddress(contextReceiver)) + 1)
        );
    }

    function createContext() public returns (TestResult memory) {
        return createContextFromParams(testParams);
    }

    function tearDown() public {
        // Check if testPrams is initialized
        if (testParams.providers.length == 0 && testParams.orders.length == 0) {
            return;
        }

        // Delete test params if initialized
        delete testParams;
        
        contextOrderCreator = DEFAULT_ORDER_CREATOR;
        contextOrderRecipient = DEFAULT_ORDER_RECIPIENT;
        contextFulfiller = DEFAULT_ORDER_FULFILLER;
        contextProvider = DEFAULT_PROVIDER;
        contextReceiver = addressToBytes21(DEFAULT_RECEIVER);
    }

    function createContextFromParams(TestParams memory params) public returns (TestResult memory) {
        // Step 1: Set up providers and their receivers
        address[] memory _providers = new address[](params.providers.length);

        for (uint256 i = 0; i < params.providers.length; i++) {
            ProviderParams memory providerParams = params.providers[i];
            createProviderWithReceivers(
                providerParams.provider,
                providerParams.receivers,
                providerParams.liquidity,
                providerParams.rate,
                providerParams.minOrderSize,
                providerParams.minDeposit
            );
            _providers[i] = providerParams.provider;
        }


        // Keep track of order IDs
        uint256 expiredOrderCount = 0;
        bytes32[] memory orderIds = new bytes32[](params.orders.length);

        // **First**, create and process expired orders
        for (uint256 i = 0; i < params.orders.length; i++) {
            if (params.orders[i].state == OrderState.Expired) {
                bytes32 orderId = _createAndProcessOrder(params.orders[i]);
                expiredOrderCount++;
                orderIds[i] = orderId;
            }
        }

        // Advance time to expire the expired orders
        if (expiredOrderCount > 0) {
            expireOrder();
        }

        // **Second**, create and process other orders
        for (uint256 i = 0; i < params.orders.length; i++) {
            if (params.orders[i].state != OrderState.Expired) {
                bytes32 orderId = _createAndProcessOrder(params.orders[i]);
                orderIds[i] = orderId;
            }
        }

        // Store the current context (providers and orders)
        for (uint256 i = 0; i < _providers.length; i++) {
            providers[_providers[i]] = getProviderFromContract(_providers[i]);
        }

        for (uint256 i = 0; i < orderIds.length; i++) {
            orders[orderIds[i]] = getOrderFromContract(orderIds[i]);
        }

        // Return TestResult with providers and orderIds
        return TestResult({
            providers: _providers,
            orderIds: orderIds
        });
    }

    function _createAndProcessOrder(OrderParams memory _orderParams) internal returns (bytes32 orderId) {
        // Create order
        (orderId, ) = createOrder(
            _orderParams.orderCreator,
            _orderParams.provider,
            _orderParams.receiver,
            _orderParams.size,
            _orderParams.recipient == address(0) ? _orderParams.orderCreator : _orderParams.recipient
        );

        // Handle order state changes
        if (_orderParams.state == OrderState.Fulfilled) {
            fulfillOrder(_orderParams.fulfiller, orderId);
        }

        if (_orderParams.state == OrderState.Stopped) {
            stopOrder(_orderParams.orderCreator, orderId);
        }

        if (_orderParams.state == OrderState.Closed) {
            // Close the order
            IUntronCore.Inflow[] memory closedOrders = new IUntronCore.Inflow[](1);
            closedOrders[0] = IUntronCore.Inflow({
                order: orderId,
                inflow: _orderParams.wasFulfilledBeforeClosing ? _orderParams.size : 0
            });
            // Prepare public values
            bytes memory publicValues = abi.encode(
                stateHash(),     // actionChainTip
                bytes32(uint256(1)),         // newStateHash
                actionChainTip(),     // latestIncludedAction
                closedOrders                 // closedOrders
            );
            bytes memory proof = abi.encodePacked(bytes32(0)); // Correctly initialized proof

            // Close orders
            closeOrders(proof, publicValues);
        }

        return orderId;
    }

    function addProvider(
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        uint256 numReceivers
    ) public returns (address _provider, bytes21[] memory _receivers) {
        bytes21[] memory receivers = new bytes21[](numReceivers);
        for (uint256 i = 0; i < numReceivers; i++) {
            receivers[i] = contextReceiver;
            incrementReceiver();
        }

        ProviderParams memory providerParams = ProviderParams({
            provider: contextProvider,
            liquidity: liquidity,
            rate: rate,
            minOrderSize: minOrderSize,
            minDeposit: minDeposit,
            receivers: receivers
        });
        testParams.providers.push(providerParams);

        _provider = contextProvider;
        _receivers = receivers;

        for (uint256 i = 0; i < receivers.length; i++) {
            providerByReceiver[receivers[i]] = contextProvider;
        }

        incrementProvider();
    }

    function addProviderWithDefaultParams(
        uint256 numReceivers
    ) public returns (address _provider, bytes21[] memory _receivers) {
        return addProvider(
            DEFAULT_LIQUIDITY,
            DEFAULT_RATE,
            DEFAULT_MIN_ORDER_SIZE,
            DEFAULT_MIN_DEPOSIT,
            numReceivers
        );
    }

    function addFulfilledOrder(
        uint256 size,
        bytes21 _receiver
    ) public returns (address _orderCreator, address _orderRecipient, address _fulfiller) {
        OrderParams memory order = OrderParams({
            orderCreator: contextOrderCreator,
            provider: providerByReceiver[_receiver],
            receiver: _receiver,
            size: size,
            state: OrderState.Fulfilled,
            wasFulfilledBeforeClosing: false,
            recipient: contextOrderRecipient,
            fulfiller: contextFulfiller
        });
        testParams.orders.push(order);

        _orderCreator = contextOrderCreator;
        _orderRecipient = contextOrderRecipient;
        _fulfiller = contextFulfiller;
        incrementOrderCreator();
        incrementOrderRecipient();
        incrementFulfiller();
    }

    function addOrder(
        uint256 size,
        OrderState state,
        bool wasFulfilledBeforeClosing,
        bytes21 _receiver
    ) public returns (address _orderCreator, address _orderRecipient) {
        OrderParams memory order = OrderParams({
            orderCreator: contextOrderCreator,
            provider: providerByReceiver[_receiver],
            receiver: _receiver,
            size: size,
            state: state,
            wasFulfilledBeforeClosing: wasFulfilledBeforeClosing,
            recipient: contextOrderRecipient,
            fulfiller: address(0)
        });
        testParams.orders.push(order);

        _orderCreator = contextOrderCreator;
        _orderRecipient = contextOrderRecipient;
        incrementOrderCreator();
        incrementOrderRecipient();
    }

    function addOrderWithDefaultParams(bytes21 _receiver) public returns (address _orderCreator, address _orderRecipient) {
        return addOrder(
            DEFAULT_ORDER_SIZE,
            DEFAULT_ORDER_STATE,
            DEFAULT_WAS_FULFILLED_BEFORE_CLOSING,
            _receiver
        );
    }

    function addFulfilledOrderWithDefaultParams(bytes21 _receiver) public returns (address _orderCreator, address _orderRecipient, address _fulfiller) {
        return addFulfilledOrder(
            DEFAULT_ORDER_SIZE,
            _receiver
        );
    }

    function addExpiredOrderWithDefaultParams(bytes21 _receiver) public returns (address _orderCreator, address _orderRecipient) {
        return addOrder(
            DEFAULT_ORDER_SIZE,
            OrderState.Expired,
            DEFAULT_WAS_FULFILLED_BEFORE_CLOSING,
            _receiver
        );
    }

    function getDefaultOrderFulfiller() public pure returns (address) {
        return DEFAULT_ORDER_FULFILLER;
    }
}