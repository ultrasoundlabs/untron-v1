// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IUntronTransfers.sol";
import "./IUntronZK.sol";
import "./IUntronFees.sol";

/// @title Interface for the UntronCore contract
/// @author Ultrasound Labs
/// @notice This interface defines the functions and structs used in the UntronCore contract.
interface IUntronCore is IUntronTransfers, IUntronFees, IUntronZK {
    /// @notice Struct representing a Tron->L2 order in the Untron protocol
    struct Order {
        // the timestamp of the order
        uint256 timestamp;
        // the creator of the order (will send USDT Tron)
        address creator;
        // the liquidity provider of the order (will receive USDT Tron in exchange for their USDT L2)
        address provider;
        // the provider's receiver of the order (will receive USDT Tron)
        bytes21 receiver;
        // the size of the order (in USDT Tron)
        uint256 size;
        // the rate of the order (in USDT L2 per 1 USDT Tron)
        // divided by 1e6 (see "bp" in UntronFees.sol)
        uint256 rate;
        // the minimum deposit in USDT Tron
        uint256 minDeposit;
        // order creator's collateral for the order (in USDT L2)
        uint256 collateral;
        // boolean indicating if the order is fulfilled. If it is then the order creator is the fulfiller.
        // if not, then it is simply the order creator.
        bool isFulfilled;
        // the transfer details for the order.
        // It can be as simple as a direct USDT L2 (zksync) transfer to the recipient,
        // or it can be a more complex transfer such as a 1inch swap of USDT L2 (zksync) to the other coin,
        // or/and a cross-chain transfer of the coin to the other network through Across bridge.
        Transfer transfer;
    }

    /// @notice Struct representing the liquidity provider in the Untron protocol
    struct Provider {
        // provider's total liquidity in USDT L2
        uint256 liquidity;
        // provider's current rate in USDT L2 per 1 USDT Tron
        uint256 rate;
        // minimum order size in USDT Tron
        uint256 minOrderSize;
        // minimum deposit in USDT Tron
        uint256 minDeposit;
        // provider's Tron addresses to receive the USDT Tron from the order creators
        bytes21[] receivers;
    }

    /// @notice Struct representing the inflow of USDT Tron to the Untron protocol.
    /// @dev This struct is created within the ZK part of the protocol.
    ///      It represents the amount of USDT Tron that the order creator has sent to the receiver address
    ///      specified in the order with specified ID.
    ///      As the ZK program is the one scanning all USDT transfers in Tron blockchain,
    ///      it is able to find all the transfers to active receivers.
    ///      Then it aggregates them into Inflow structs and sends to the onchain part of the protocol.
    ///      Important note: ZK program doesn't accept USDT transfers less than minDeposit (see /program in the repo)
    struct Inflow {
        // the order ID
        bytes32 order;
        // the inflow amount in USDT Tron
        uint256 inflow;
    }

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
    event OrderChanged(bytes32 orderId);
    event OrderStopped(bytes32 orderId);
    event ActionChainUpdated(
        bytes32 prevOrderId, uint256 timestamp, bytes21 receiver, uint256 minDeposit, uint256 size
    );
    event OrderFulfilled(bytes32 indexed orderId, address fulfiller);
    event OrderClosed(bytes32 indexed orderId, address relayer);
    event RelayUpdated(address relayer, bytes32 stateHash);
    event ProviderUpdated(
        address indexed provider,
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        bytes21[] receivers
    );
    event ReceiverFreed(address provider, bytes21 receiver);

    function providers(address provider) external view returns (Provider memory);
    function isReceiverBusy(bytes21 receiver) external view returns (bytes32);
    function receiverOwners(bytes21 receiver) external view returns (address);
    function orders(bytes32 orderId) external view returns (Order memory);

    function actionChainTip() external view returns (bytes32);
    function actions(bytes32 action) external view returns (bool);

    function genesisState() external view returns (bytes memory);
    function stateHash() external view returns (bytes32);
    function stateUpgradeBlock() external view returns (uint256);

    function maxOrderSize() external view returns (uint256);
    function requiredCollateral() external view returns (uint256);
    function orderTtlMillis() external view returns (uint256);

    /// @notice Updates the UntronCore-related variables
    /// @param _maxOrderSize The new maximum size of an order that can be created
    /// @param _requiredCollateral The new required collateral for creating an order
    /// @param _orderTtlMillis The new time-to-live for an order in milliseconds
    function setCoreVariables(uint256 _maxOrderSize, uint256 _requiredCollateral, uint256 _orderTtlMillis) external;

    /// @notice The order creation function
    /// @param provider The address of the liquidity provider owning the Tron receiver address.
    /// @param receiver The address of the Tron receiver address
    ///                that's used to perform a USDT transfer on Tron.
    /// @param size The maximum size of the order in USDT Tron.
    /// @param rate The "USDT L2 per 1 USDT Tron" rate of the order.
    /// @param transfer The transfer details.
    ///                 They'll be used in the fulfill or closeOrders functions to send respective
    ///                 USDT L2 to the order creator or convert them into whatever the order creator wants to receive
    ///                 for their USDT Tron.
    function createOrder(address provider, bytes21 receiver, uint256 size, uint256 rate, Transfer calldata transfer)
        external;

    /// @notice Changes the transfer details of an order.
    /// @param orderId The ID of the order to change.
    /// @param transfer The new transfer details.
    /// @dev The transfer details can only be changed before the order is fulfilled.
    function changeOrder(bytes32 orderId, Transfer calldata transfer) external;

    /// @notice Stops the order and returns the remaining liquidity to the provider.
    /// @param orderId The ID of the order to stop.
    /// @dev The order can only be stopped before it's fulfilled.
    ///      Closing and stopping the order are different things.
    ///      Closing means that provider's funds are unlocked to either the order creator or the provider
    ///      as the order completed its listening cycle.
    ///      Stopping means that the order no longer needs listening for new USDT Tron transfers
    ///      and won't be fulfilled.
    function stopOrder(bytes32 orderId) external;

    /// @notice Helper function that calculates the fulfiller's total expense and income given the order IDs.
    /// @param _orderIds The IDs of the orders.
    /// @return totalExpense The total expense in USDT L2.
    /// @return totalProfit The total profit in USDT L2.
    function calculateFulfillerTotal(bytes32[] calldata _orderIds)
        external
        view
        returns (uint256 totalExpense, uint256 totalProfit);

    /// @notice Fulfills the orders by sending their ask in advance.
    /// @param _orderIds The IDs of the orders.
    /// @param total The total amount of USDT L2 to transfer.
    /// @dev Fulfillment exists because ZK proofs that actually *close* the orders
    ///      are published every 60-90 minutes. This means that provider's funds
    ///      will only be unlocked to them or to order creators with this delay.
    ///      However, we want the order creators to receive the funds ASAP.
    ///      Fulfillers send order creators' ask in advance when they see that their USDT
    ///      transfer happened on Tron blockchain, but wasn't ZK proven yet.
    ///      After the transfer is ZK proven, they'll receive the full amount of
    ///      USDT L2.
    ///      Fulfillers take the fee for the service, which depends on complexity of the transfer
    ///      (if it requires a swap or not, what's the chain of the transfer, etc).
    function fulfill(bytes32[] calldata _orderIds, uint256 total) external;

    /// @notice Closes the orders and sends the funds to the providers or order creators, if not fulfilled.
    /// @param proof The ZK proof.
    /// @param publicValues The public values for the proof and order closure.
    /// @param newState The new state of the ZK engine.
    function closeOrders(bytes calldata proof, bytes calldata publicValues, bytes calldata newState) external;

    /// @notice Sets the liquidity provider details.
    /// @param liquidity The liquidity of the provider in USDT L2.
    /// @param rate The rate (USDT L2 per 1 USDT Tron) of the provider.
    /// @param minOrderSize The minimum size of the order in USDT Tron.
    /// @param minDeposit The minimum amount the order creator can transfer to the receiver, in USDT Tron.
    ///                   This is needed for so-called "reverse swaps", when the provider is
    ///                   actually a normal order creator who wants to swap USDT L2 for USDT Tron,
    ///                   and the order creator (who creates the orders) is an automated entity,
    ///                   called "sender", that accepts such orders and performs transfers on Tron network.
    ///                   order creators doing reverse swaps usually want to receive the entire order size
    ///                   in a single transfer, hence the need for minDeposit.
    ///                   minOrderSize == liquidity * rate signalizes for senders that the provider
    ///                   is a order creator performing a reverse swap.
    /// @param receivers The provider's Tron addresses that are used to receive USDT Tron.
    ///                  The more receivers the provider has, the more concurrent orders the provider can have.
    function setProvider(
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        bytes21[] calldata receivers
    ) external;
}
