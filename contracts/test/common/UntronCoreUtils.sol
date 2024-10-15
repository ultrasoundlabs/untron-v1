// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/interfaces/IUntronCore.sol";
import "../../src/UntronCore.sol";
import "../../src/UntronTransfers.sol";
import "../../src/UntronFees.sol";
import "../../src/UntronZK.sol";
import "../mocks/MockUSDT.sol";
import "../mocks/MockLifi.sol";
import "@sp1-contracts/SP1MockVerifier.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract UntronCoreUtils is Test {
    // Admin is always address(1)
    address admin = address(1);

    // Contract instances
    UntronCore public untron;
    MockUSDT public usdt;
    MockLifi public lifi;
    SP1MockVerifier public sp1Verifier;
        
    // Constants
    uint256 public constant ORDER_TTL = 300; // 5 minutes in seconds

    // Constructor to initialize with the UntronCore and MockUSDT contracts
    constructor() {
        lifi = new MockLifi();
        sp1Verifier = new SP1MockVerifier();
        usdt = new MockUSDT();
        untron = new UntronCore();
    }

    function setUp() public virtual {
        // Set up can remain empty if needed
    }

    /// @notice Mints USDT to a recipient.
    function mintUSDT(address recipient, uint256 amount) public {
        vm.startPrank(admin);
        usdt.mint(recipient, amount);
        vm.stopPrank();
    }

    /// @notice Approves USDT spending for an owner.
    function approveUSDT(address owner, address spender, uint256 amount) public {
        vm.startPrank(owner);
        usdt.approve(spender, amount);
        vm.stopPrank();
    }

    function createProviderWithRandomReceivers(
        address provider,
        uint256 numReceivers,
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit
    ) public returns (bytes21[] memory receivers) {
        receivers = new bytes21[](numReceivers);
        mintUSDT(provider, liquidity);
        approveUSDT(provider, address(untron), liquidity);

        vm.startPrank(provider);
        for (uint256 i = 0; i < numReceivers; i++) {
            bytes20 addr = bytes20(vm.addr(uint256(keccak256(abi.encodePacked("receiver", provider, i)))));
            receivers[i] = bytes21(bytes.concat(hex"41", addr));
        }

        untron.setProvider(
            liquidity,
            rate,
            minOrderSize,
            minDeposit,
            receivers
        );
        vm.stopPrank();
    }

    /// @notice Supplies additional liquidity to a provider.
    function supplyProvider(address provider, uint256 amount) public {
        mintUSDT(provider, amount);
        approveUSDT(provider, address(untron), amount);

        vm.startPrank(provider);
        IUntronCore.Provider memory providerInfo = untron.providers(provider);
        untron.setProvider(
            providerInfo.liquidity + amount,
            providerInfo.rate,
            providerInfo.minOrderSize,
            providerInfo.minDeposit,
            providerInfo.receivers
        );
        vm.stopPrank();
    }

    /// @notice Creates an order with the first available receiver.
    function createOrderWithFirstFreeReceiver(
        address orderCreator_,
        address provider,
        uint256 size
    ) public returns (bytes32 orderId, bytes21 receiver) {
        IUntronCore.Provider memory providerInfo = untron.providers(provider);
        require(providerInfo.receivers.length > 0, "No receivers available");

        // Find the first free receiver
        for (uint256 i = 0; i < providerInfo.receivers.length; i++) {
            if (untron.isReceiverBusy(providerInfo.receivers[i]) == bytes32(0)) {
                receiver = providerInfo.receivers[i];
                break;
            }
        }
        require(receiver != bytes21(0), "No free receiver found");

        // Mint collateral to orderCreator
        mintUSDT(orderCreator_, untron.requiredCollateral());
        approveUSDT(orderCreator_, address(untron), untron.requiredCollateral());

        vm.startPrank(orderCreator_);
        IUntronTransfers.Transfer memory transfer = IUntronTransfers.Transfer({
            directTransfer: true,
            data: abi.encode(orderCreator_)
        });

        untron.createOrder(provider, receiver, size, providerInfo.rate, transfer);
        vm.stopPrank();

        orderId = untron.isReceiverBusy(receiver);
    }

    /// @notice Expires an order by advancing time.
    function expireOrder() public {
        vm.warp(block.timestamp + ORDER_TTL + 1);
    }

    /// @notice Removes all receivers from a provider.
    function removeAllReceiversFromProvider(address provider) public {
        IUntronCore.Provider memory providerInfo = untron.providers(provider);

        vm.startPrank(provider);
        untron.setProvider(
            providerInfo.liquidity,
            providerInfo.rate,
            providerInfo.minOrderSize,
            providerInfo.minDeposit,
            new bytes21[](0)
        );
        vm.stopPrank();
    }

    /// @notice Fulfills an order.
    function fulfillOrder(address fulfiller_, bytes32 orderId) public {
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        (uint256 expense,) = untron.calculateFulfillerTotal(orderIds);

        mintUSDT(fulfiller_, expense);
        approveUSDT(fulfiller_, address(untron), expense);

        vm.startPrank(fulfiller_);
        untron.fulfill(orderIds, expense);
        vm.stopPrank();
    }

    /// @notice Changes an order's transfer details.
    function changeOrder(
        address orderCreator_,
        bytes32 orderId,
        IUntronTransfers.Transfer memory newTransfer
    ) public {
        vm.startPrank(orderCreator_);
        untron.changeOrder(orderId, newTransfer);
        vm.stopPrank();
    }

    /// @notice Stops an order.
    function stopOrder(address orderCreator_, bytes32 orderId) public {
        vm.startPrank(orderCreator_);
        untron.stopOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Calculates the fulfiller's total expense and profit.
    function calculateFulfillerTotal(bytes32[] memory orderIds)
        public
        view
        returns (uint256 totalExpense, uint256 totalProfit)
    {
        return untron.calculateFulfillerTotal(orderIds);
    }

    /// @notice Closes orders by providing a proof and public values.
    function closeOrders(
        bytes memory proof,
        bytes memory publicValues
    ) public {
        vm.startPrank(admin);
        untron.closeOrders(proof, publicValues);
        vm.stopPrank();
    }

    function conversion(uint256 size, uint256 rate, uint256 fixedFee, bool includeRelayerFee)
    public pure returns (uint256 value, uint256 _relayerFee)
    {
        
        // convert size into USDT L2 based on the rate
        uint256 out = (size * rate / 1e6);
        // if the relayer fee is included, subtract it from the converted size
        if (includeRelayerFee) {
            // subtract relayer fee from the converted size
            value = getRelayerFee(out);
            // and write the fee to the fee variable
            _relayerFee = out - value;
        } else {
            // if the relayer fee is not included, the value is just converted size (size * rate)
            value = out;
        }
        // subtract fixed fee from the output value
        value -= fixedFee;
    }

    // Overridden or additional functions
    function createProviderWithReceivers(
        address provider,
        bytes21[] memory receivers,
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit
    ) public {
        mintUSDT(provider, liquidity);
        approveUSDT(provider, address(untron), liquidity);

        vm.startPrank(provider);
        untron.setProvider(
            liquidity,
            rate,
            minOrderSize,
            minDeposit,
            receivers
        );
        vm.stopPrank();
    }

    function createOrder(
        address orderCreator_,
        address provider,
        bytes21 receiver,
        uint256 size,
        address recipient
    ) public returns (bytes32 orderId, bytes21 receiver_) {
        // Mint collateral to orderCreator
        mintUSDT(orderCreator_, untron.requiredCollateral());
        approveUSDT(orderCreator_, address(untron), untron.requiredCollateral());

        vm.startPrank(orderCreator_);
        IUntronTransfers.Transfer memory transfer = IUntronTransfers.Transfer({
            directTransfer: true,
            data: abi.encode(recipient)
        });

        untron.createOrder(provider, receiver, size, untron.providers(provider).rate, transfer);
        vm.stopPrank();

        orderId = untron.isReceiverBusy(receiver);
        receiver_ = receiver;
    }
    
    function stateHash() public view returns (bytes32) {
        return untron.stateHash();
    }

    function actionChainTip() public view returns (bytes32) {
        return untron.actionChainTip();
    }

    // TODO: Improve
    function getRelayerFee(uint256 amount) public pure returns (uint256) {
        // Calculate the relayer fee as a percentage of the amount
        // I.e since the fee is 100/1e6 (0.0001) [0.01%], we multiply it by the amount to obtain the fee
        return amount * 100 / 1e6;
    }

    // TODO: Improve
    function getFulfillerFee() public pure returns (uint256) {
        return 0.01e6;
    }

    function addressToBytes21(address addr) public pure returns (bytes21) {
        return bytes21(bytes.concat(hex"41", bytes20(addr)));
    }


    function bytes21ToAddress(bytes21 bytes21Addr) public pure returns (address) {
        // Remove the first byte (0x41) and cast to address
        return address(uint160(uint168(bytes21Addr)));
    }

    function addressToUint256(address addr) public pure returns (uint256) {
        return uint256(uint160(addr));
    }
    
    function getProviderFromContract(address provider) public view returns (IUntronCore.Provider memory) {
        return untron.providers(provider);
    }

    function getOrderFromContract(bytes32 orderId) public view returns (IUntronCore.Order memory) {
        return untron.orders(orderId);
    }
}
