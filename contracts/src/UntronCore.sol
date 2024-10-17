// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IUntronCore.sol";
import "./UntronTransfers.sol";
import "./UntronTools.sol";
import "./UntronFees.sol";
import "./UntronZK.sol";

/// @title Core logic for Untron protocol
/// @author Ultrasound Labs
/// @notice This contract contains the main logic of the Untron protocol.
///         It's designed to be fully upgradeable and modular, with each module being a separate contract.
contract UntronCore is Initializable, OwnableUpgradeable, UntronTransfers, UntronFees, UntronZK, IUntronCore {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the core with the provided parameters.
    /// @dev This function grants the ownership to msg.sender.
    ///      Owner can upgrade the contract and dynamic values (see set...Variables functions)
    function initialize(bytes calldata state) public initializer {
        _transferOwnership(msg.sender);

        // initialize genesis state
        genesisState = state;
        stateHash = sha256(state);
        stateUpgradeBlock = block.number;
        genesisBlock = block.number;
    }

    // Action is an act of triggering the receiver address
    // in the ZK program's state. It can be either order creation or order stop.
    // actionChain is a hash chain of all actions ever performed.
    bytes32 public actionChainTip;
    // actions is a mapping if the action has ever been created.
    mapping(bytes32 => bool) public actions;

    bytes public genesisState;
    uint256 public genesisBlock; // ZKsync Era block number when the genesis state was set

    // State is an internal record of all Tron blockchain data and Untron orders used by the ZK program.
    // It's a bincode-serialized State Rust struct. The genesis state is stored in genesisState for easy reconstruction.
    // Whenever the state is updated, its hash is set in stateHash,
    // and the state upgrade block is set to the current block number.
    // The state is updated by the relayer whenever a new ZK proof of the program is executed.
    bytes32 public stateHash;
    // latestIncludedAction is the latest action that was included in the ZK proof.
    bytes32 public latestIncludedAction;
    // stateUpgradeBlock is the ZKsync Era block number when the state was last updated.
    uint256 public stateUpgradeBlock;

    // maxOrderSize is the maximum size of an order that can be created, in USDT Tron.
    uint256 public maxOrderSize;
    // requiredCollateral is the amount of USDT L2 that must be sent with the order to create it.
    // It can then be claimed back if the order is properly closed.
    uint256 public requiredCollateral;
    // orderTtlMillis is the time-to-live of an order in milliseconds.
    uint256 public orderTtlMillis;

    /// @inheritdoc IUntronCore
    function setCoreVariables(uint256 _maxOrderSize, uint256 _requiredCollateral, uint256 _orderTtlMillis)
        external
        onlyOwner
    {
        require(_maxOrderSize > 0 &&  _requiredCollateral > 0 &&  _orderTtlMillis> 0, " Params Should be greater than 0");
     
        maxOrderSize = _maxOrderSize;
        requiredCollateral = _requiredCollateral;
        orderTtlMillis = _orderTtlMillis;
    }

    /// @notice Mapping to store provider details.
    mapping(address => Provider) internal _providers;
    /// @notice Mapping to store whether a receiver is busy with an order.
    mapping(bytes21 => bytes32) public isReceiverBusy;
    /// @notice Mapping to store the owner (provider) of a receiver.
    mapping(bytes21 => address) public receiverOwners;
    /// @notice Mapping to store order details by order ID.
    mapping(bytes32 => Order) internal _orders;

    /// @notice Returns the provider details for a given address
    /// @param provider The address of the provider
    /// @return Provider struct containing the provider's details
    function providers(address provider) external view returns (Provider memory) {
        return _providers[provider];
    }

    /// @notice Returns the order details for a given order ID
    /// @param orderId The ID of the order
    /// @return Order struct containing the order details
    function orders(bytes32 orderId) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @notice Updates the action chain and returns the new tip of the chain.
    /// @param receiver The address of the receiver.
    /// @param minDeposit The minimum deposit amount.
    /// @return _actionChainTip The new action chain tip.
    /// @dev must only be used in _createOrder and _freeReceiver
    function _updateActionChain(bytes21 receiver, uint256 minDeposit, uint256 size)
        internal
        returns (bytes32 _actionChainTip)
    {
        // action chain is a hash chain of the order-related, onchain-initiated actions.
        // Action consists of timestamp in Tron format, Tron receiver address, minimum deposit amount, and order size.
        // It's used to start and stop orders. If the order is stopped, minimum deposit amount is not used.
        // We're utilizing Tron timestamp to enforce the ZK program to follow all Untron actions respective to the Tron blockchain.
        // ABI: (bytes32, uint256, address, uint256, uint256)
        uint256 tronTimestamp = unixToTron(block.timestamp);
        _actionChainTip = sha256(abi.encode(actionChainTip, tronTimestamp, receiver, minDeposit, size));
        emit ActionChainUpdated(actionChainTip, tronTimestamp, receiver, minDeposit, size);

        // actionChainTip stores the latest action (aka order id), that is, the tip of the action chain.
        actionChainTip = _actionChainTip;
        // mark the action as created
        actions[_actionChainTip] = true;
    }

    /// @notice Performs an illegitimate action chain update.
    /// @param receiver The address of the receiver.
    /// @param minDeposit The minimum deposit amount.
    /// @param size The order size.
    /// @dev The caller must be an owner. This function must only be used in case of a bug in the system.
    function updateActionChain(bytes21 receiver, uint256 minDeposit, uint256 size) external onlyOwner {
        _updateActionChain(receiver, minDeposit, size);
    }


    /// @notice Checks if the order is expired.
    /// @param orderId The ID of the order.
    /// @return bool True if the order is expired, false otherwise.
    /// @dev The order is expired if the current timestamp is greater than the order timestamp + orderTtlMillis.
    function isOrderExpired(bytes32 orderId) internal view returns (bool) {
        return _orders[orderId].timestamp + orderTtlMillis < unixToTron(block.timestamp);
    }

    /// @inheritdoc IUntronCore
    function createOrder(address provider, bytes21 receiver, uint256 size, uint256 rate, Transfer calldata transfer)
        external 
    {
        // collect collateral from the order creator
        internalTransferFrom(msg.sender, requiredCollateral);


        // amount is the amount of USDT L2 that will be taken from the provider
        // based on the order size (which is in USDT Tron) and provider's rate
        (uint256 amount,) = conversion(size, rate, false, false);

        require(amount>0," Amount Should be greater Than Zero");
        
        uint256 providerMinDeposit = _providers[provider].minDeposit;

        if (isReceiverBusy[receiver] != bytes32(0)) {
            // if the receiver is busy, check if the order that made it busy is not expired yet
            require(isOrderExpired(isReceiverBusy[receiver]), "Receiver is busy");
            // if it's expired, stop it manually
            _freeReceiver(receiver);
        }
        require(receiverOwners[receiver] == provider, "Receiver is not owned by provider");
        require(_providers[provider].liquidity >= amount, "Provider does not have enough liquidity");
        require(rate == _providers[provider].rate, "Rate does not match provider's rate");
        require(_providers[provider].minOrderSize <= size, "Order size is less than minimum");
        require(size <= maxOrderSize, "Size is greater than max order size");

        // subtract the amount from the provider's liquidity
        _providers[provider].liquidity -= amount;

        // create the order ID and update the action chain.
        // order ID is the tip of the action chain when the order was created.
        bytes32 orderId = _updateActionChain(receiver, providerMinDeposit, size);
        // set the receiver as busy to prevent double orders
        isReceiverBusy[receiver] = orderId;
        uint256 timestamp = unixToTron(block.timestamp);
        // store the order details in storage
        _orders[orderId] = Order({
            timestamp: timestamp,
            creator: msg.sender,
            provider: provider,
            receiver: receiver,
            size: size,
            rate: rate,
            minDeposit: providerMinDeposit,
            collateral: requiredCollateral,
            isFulfilled: false,
            transfer: transfer
        });

        // Emit OrderCreated event
        emit OrderCreated(orderId, timestamp, msg.sender, provider, receiver, size, rate, providerMinDeposit);
    }

    /// @inheritdoc IUntronCore
    function changeOrder(bytes32 orderId, Transfer calldata transfer) external {
        require(
            _orders[orderId].creator == msg.sender && !_orders[orderId].isFulfilled, "Only creator can change the order"
        );

        // change the transfer details
        _orders[orderId].transfer = transfer;

        // Emit OrderChanged event
        emit OrderChanged(orderId);
    }

    /// @inheritdoc IUntronCore
    function stopOrder(bytes32 orderId) external {
        require(
            _orders[orderId].creator == msg.sender && !_orders[orderId].isFulfilled,
            "Only creator can stop the order"
        );
        require(!isOrderExpired(orderId), "Cannot stop an expired order");

        // update the action chain with stop action
        _freeReceiver(_orders[orderId].receiver);

        // return the liquidity back to the provider
        _providers[_orders[orderId].provider].liquidity += _orders[orderId].size;

        // refund the collateral to the order creator
        internalTransfer(usdt, msg.sender, _orders[orderId].collateral);

        // delete the order because it won't be fulfilled/closed
        // (stopOrder assumes that the order creator sent nothing)
        delete _orders[orderId];

        // Emit OrderStopped event
        emit OrderStopped(orderId);
    }

    /// @notice Calculates the amount and fulfiller fee for a given order
    /// @param order The Order struct containing order details
    /// @return amount The amount of USDT L2 that the fulfiller will have to send
    /// @return _fulfillerFee The fee for the fulfiller
    function _getAmountAndFee(Order memory order) internal view returns (uint256 amount, uint256 _fulfillerFee) {
        // calculate the amount of USDT L2 that the fulfiller will have to send
        (amount, _fulfillerFee) = conversion(order.size, order.rate, true, true);
    }

    /// @notice Retrieves the active order for a given receiver
    /// @param receiver The address of the receiver
    /// @return Order struct containing the active order details
    function _getActiveOrderByReceiver(bytes21 receiver) internal view returns (Order memory) {
        // get the active order ID for the receiver
        bytes32 activeOrderId = isReceiverBusy[receiver];
        // get the order details
        return _orders[activeOrderId];
    }

    /// @inheritdoc IUntronCore
    function calculateFulfillerTotal(bytes32[] calldata _orderIds)
        external
        view
        returns (uint256 totalExpense, uint256 totalProfit)
    {
        // iterate over the order IDs
        for (uint256 i = 0; i < _orderIds.length; i++) {
            Order memory order = _orders[_orderIds[i]];
            (uint256 amount, uint256 fulfillerFee) = _getAmountAndFee(order);

            // add the amount to the total expense and the fee to the total profit
            totalExpense += amount;
            totalProfit += fulfillerFee;
        }
    }

    /// @inheritdoc IUntronCore
    function fulfill(bytes32[] calldata _orderIds, uint256 total) external {
        // take the declared amount of USDT L2 from the fulfiller
        internalTransferFrom(msg.sender, total);
        // this variable will be used to calculate how much the contract sent to the order creators.
        // this number must be equal to "total" to prevent the fulfiller from stealing the funds in the contract.
        uint256 expectedTotal;

        // iterate over the order IDs
        for (uint256 i = 0; i < _orderIds.length; i++) {
            // get the order
            Order memory order = _orders[_orderIds[i]];

            require(order.isFulfilled == false, "Order already fulfilled");

            (uint256 amount,) = _getAmountAndFee(order);

            // account for the spent amount in our accounting variable
            expectedTotal += amount;

            // perform the transfer
            require(smartTransfer(order.transfer, amount), "Transfer failed");

            // refund the collateral to the order creator
            internalTransfer(usdt, order.creator, order.collateral);

            // update action chain to free the receiver address
            _freeReceiver(order.receiver);

            // update the order details

            // to prevent from modifying the order after it's fulfilled
            _orders[_orderIds[i]].creator = msg.sender;
            // to make fulfiller receive provider's USDT L2 after the ZK proof is published
            _orders[_orderIds[i]].transfer.directTransfer = true;
            _orders[_orderIds[i]].transfer.data = abi.encode(msg.sender);
            // set the fulfilled order as isFullfilled true
            _orders[_orderIds[i]].isFulfilled = true;
            // set the collateral to 0 to prevent refunding it twice or slashing the creator wrongfully
            _orders[_orderIds[i]].collateral = 0;

            // Emit OrderFulfilled event
            emit OrderFulfilled(_orderIds[i], msg.sender);
        }

        // check that the total amount of USDT L2 sent is less or equal to the declared amount
        require(total >= expectedTotal, "Total does not match");

        // refund the fulfiller for the USDT L2 that was sent in excess
        if (expectedTotal < total) {
            internalTransfer(usdt, msg.sender, total - expectedTotal);
        }
    }

    /// @notice Closes the orders and sends the funds to the providers or order creators, if not fulfilled.
    /// @param proof The ZK proof.
    /// @param publicValues The public values for the proof and order closure.
    function closeOrders(bytes calldata proof, bytes calldata publicValues) external {
        // verify the ZK proof with the public values
        // verifying logic is defined in the UntronZK contract.
        // currently it wraps SP1 zkVM verifier.
        verifyProof(proof, publicValues);

        (
            // old state hash is the state print from the previous run of the ZK program. (stateHash)
            bytes32 oldStateHash,
            // new state hash is the state print from the new run of the ZK program.
            bytes32 newStateHash,
            // the latest action that was included in the program's inputs (must have been the tip in the SC at some point)
            bytes32 _latestIncludedAction,
            // closed orders are the orders that are being closed in this run of the ZK program.
            Inflow[] memory closedOrders
        ) = abi.decode(publicValues, (bytes32, bytes32, bytes32, Inflow[]));

        // check that the old state hash is equal to the current state hash
        // this is needed to prevent the relayer from modifying the state in the ZK program.
        require(oldStateHash == stateHash, "Old state hash is invalid");

        // update the state hash
        stateHash = newStateHash;

        require(actions[_latestIncludedAction], "Latest included action is invalid");
        latestIncludedAction = _latestIncludedAction;

        // this variable is used to calculate the total fee that the protocol owner (DAO) will receiver for relayer services
        uint256 totalFee;

        // iterate over the closed orders
        for (uint256 i = 0; i < closedOrders.length; i++) {
            // get the order ID
            bytes32 orderId = closedOrders[i].order;

            // get the minimum inflow amount.
            // minInflow is the minimum number between the inflow amount on Tron and the order size.
            // this is needed so that the order creator/fulfiller doesn't get more than the order size (locked liquidity).
            uint256 minInflow =
                closedOrders[i].inflow < _orders[orderId].size ? closedOrders[i].inflow : _orders[orderId].size;

            // calculate the amount the order creator/fulfiller will receive and fee for the protocol
            // if the order is fulfilled, we don't need to include the fulfiller fee for the relayer
            (uint256 amount, uint256 fee) =
                conversion(minInflow, _orders[orderId].rate, true, _orders[orderId].isFulfilled ? false : true);
            // add the fee to the total fee
            totalFee += fee;

            // perform the transfer
            smartTransfer(_orders[orderId].transfer, amount);

            // if the order creator didn't send anything, slash the collateral by sending it to the protocol owner
            // otherwise refund the collateral to the order creator
            // NOTE: at fulfill() and stopOrder() we set the collateral to 0 so those actions won't lead
            // to slashing even if the order creator sent nothing
            internalTransfer(usdt, minInflow == 0 ? owner() : _orders[orderId].creator, _orders[orderId].collateral);

            if (!_orders[orderId].isFulfilled) {
                // if the order is not fulfilled, update the action chain to free the receiver address
                _freeReceiver(_orders[orderId].receiver);
            }

            // TODO: there might be a conversion bug idk

            // if not entire size is sent, send the remaining liquidity back to the provider
            (uint256 remainingLiquidity,) =
                conversion(_orders[orderId].size - minInflow, _orders[orderId].rate, false, false);
            _providers[_orders[orderId].provider].liquidity += remainingLiquidity;

            // delete the order from storage
            delete _orders[orderId];

            // emit the OrderClosed event
            emit OrderClosed(orderId, msg.sender);
        }

        // transfer the fee to the protocol
        internalTransfer(usdt, owner(), totalFee);

        // update the state upgrade block
        stateUpgradeBlock = block.number;

        // emit the RelayUpdated event
        emit RelayUpdated(msg.sender, stateHash);
    }

    /// @inheritdoc IUntronCore
    function setProvider(
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        bytes21[] calldata receivers
    ) external {
    
        require(liquidity >0 && rate >0 && minOrderSize >0 && minDeposit > 0,"Params Should be Greater Than Zero");

        // get provider's current liquidity
        uint256 currentLiquidity = _providers[msg.sender].liquidity;

        // if the provider's current liquidity is less than the new liquidity,
        // the provider needs to deposit the difference
        if (currentLiquidity < liquidity) {
            // transfer the difference from the provider to the contract
            internalTransferFrom(msg.sender, liquidity - currentLiquidity);
        } else if (currentLiquidity > liquidity) {
            // if the provider's current liquidity is greater than the new liquidity,
            // the provider wants to withdraw the difference

            // transfer the difference from the contract to the provider
            internalTransfer(usdt, msg.sender, currentLiquidity - liquidity);
        }

        // update the provider's liquidity
        _providers[msg.sender].liquidity = liquidity;

        // update the provider's rate
       
        _providers[msg.sender].rate = rate;
        require(minDeposit <= minOrderSize, "Min deposit is greater than min order size");
        // update the provider's minimum order size
        _providers[msg.sender].minOrderSize = minOrderSize;
        // update the provider's minimum deposit
        _providers[msg.sender].minDeposit = minDeposit;

        bytes21[] memory currentReceivers = _providers[msg.sender].receivers;
        // iterate over current receivers to ensure all are not busy or busy with already expired orders
        for (uint256 i = 0; i < currentReceivers.length; i++) {
            // if the receiver is already busy, ensure that the order is expired
            if (isReceiverBusy[currentReceivers[i]] != bytes32(0)) {
                require(
                    isOrderExpired(isReceiverBusy[currentReceivers[i]]),
                    "One of the current receivers is busy with an unexpired order"
                );
                // set the receiver as not busy
                _freeReceiver(currentReceivers[i]);
                // set the receiver owner to zero address
                receiverOwners[currentReceivers[i]] = address(0);
            }
        }

        // update the provider's receivers
        _providers[msg.sender].receivers = receivers;

        // check that the receivers are not already owned by another provider
        for (uint256 i = 0; i < receivers.length; i++) {
            require(
                receiverOwners[receivers[i]] == address(0) || receiverOwners[receivers[i]] == msg.sender,
                "Receiver is already owned by another provider"
            );
            // set the receiver owner
            receiverOwners[receivers[i]] = msg.sender;
        }

        // Emit ProviderUpdated event
        emit ProviderUpdated(msg.sender, liquidity, rate, minOrderSize, minDeposit, receivers);
    }

    /// @notice Frees the receiver by setting it as not busy and updating the action chain with closure action.
    /// @param receiver The address of the receiver to be freed
    /// @dev implements checks if the closure is legitimate;
    function _freeReceiver(bytes21 receiver) internal {
        // check if receiver is busy first. If not this is a consistency issue.
        require(isReceiverBusy[receiver] != bytes32(0), "Receiver must be busy when trying to free it");
        // set the receiver as not busy
        isReceiverBusy[receiver] = bytes32(0);
        // update the action chain with closure action
        _updateActionChain(receiver, 0, 0);
        // Emit ReceiverFreed event
        emit ReceiverFreed(receiverOwners[receiver], receiver);
    }
}
