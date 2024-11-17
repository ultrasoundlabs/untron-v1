// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./UntronCoreBase.t.sol";

contract SetProviderTest is UntronCoreBase {
    constructor() UntronCoreBase() {}

    event ProviderUpdated(
        address indexed provider,
        uint256 liquidity,
        uint256 rate,
        uint256 minOrderSize,
        uint256 minDeposit,
        bytes21[] receivers
    );

    /// @notice Test for registering a new provider successfully
    function test_setProvider_SuccessfulRegistration() public {
        // Given: A user who is not currently a provider
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6; // 1,000 USDT
        uint256 rate = 1e6; // Rate of 1
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](2);
        receivers[0] = addressToBytes21(vm.addr(200));
        receivers[1] = addressToBytes21(vm.addr(201));

        // Mint and approve USDT to the provider
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        // Capture the ProviderUpdated event
        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, liquidity, rate, minOrderSize, minDeposit, receivers);

        // When: The provider sets up their profile
        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify provider's information
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.liquidity, liquidity, "Provider's liquidity should be set correctly");
        assertEq(provider.rate, rate, "Provider's rate should be set correctly");
        assertEq(provider.minOrderSize, minOrderSize, "Provider's minOrderSize should be set correctly");
        assertEq(provider.minDeposit, minDeposit, "Provider's minDeposit should be set correctly");
        assertEq(provider.receivers.length, receivers.length, "Provider should have correct number of receivers");

        // Verify receivers' ownership
        for (uint256 i = 0; i < receivers.length; i++) {
            address receiverOwner = untron.receiverOwners(receivers[i]);
            assertEq(receiverOwner, providerAddress, "Receiver should be owned by the provider");
        }

        // Verify USDT transfer to the contract
        uint256 contractBalance = usdt.balanceOf(address(untron));
        assertEq(contractBalance, liquidity, "Contract should have received the provider's liquidity");

        // Verify provider's USDT balance decreased
        uint256 providerBalance = usdt.balanceOf(providerAddress);
        assertEq(providerBalance, 0, "Provider's USDT balance should be zero after depositing liquidity");
    }

    /// @notice Test for increasing provider's liquidity
    function test_setProvider_IncreaseLiquidity() public {
        // Given: An existing provider with initial liquidity
        address providerAddress = vm.addr(100);
        uint256 initialLiquidity = 1000e6; // 1,000 USDT
        uint256 additionalLiquidity = 500e6; // Additional 500 USDT
        uint256 newLiquidity = initialLiquidity + additionalLiquidity;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](1);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Initial setup
        mintUSDT(providerAddress, initialLiquidity);
        approveUSDT(providerAddress, address(untron), initialLiquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(initialLiquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Mint and approve additional USDT for increasing liquidity
        mintUSDT(providerAddress, additionalLiquidity);
        approveUSDT(providerAddress, address(untron), additionalLiquidity);

        // Capture the ProviderUpdated event
        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, newLiquidity, rate, minOrderSize, minDeposit, receivers);

        // When: The provider increases their liquidity
        vm.startPrank(providerAddress);
        untron.setProvider(newLiquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify provider's liquidity is updated
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.liquidity, newLiquidity, "Provider's liquidity should be increased");

        // Verify additional USDT transfer to the contract
        uint256 contractBalance = usdt.balanceOf(address(untron));
        assertEq(contractBalance, newLiquidity, "Contract should have received the additional liquidity");

        // Verify provider's USDT balance decreased accordingly
        uint256 expectedProviderBalance = 0; // All USDT transferred
        uint256 providerBalance = usdt.balanceOf(providerAddress);
        assertEq(providerBalance, expectedProviderBalance, "Provider's USDT balance should be zero");
    }

    /// @notice Test for decreasing provider's liquidity
    function test_setProvider_DecreaseLiquidity() public {
        // Given: An existing provider with initial liquidity
        address providerAddress = vm.addr(100);
        uint256 initialLiquidity = 1000e6; // 1,000 USDT
        uint256 reducedLiquidity = 600e6; // Reduce to 600 USDT
        uint256 liquidityToWithdraw = initialLiquidity - reducedLiquidity;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](1);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Initial setup
        mintUSDT(providerAddress, initialLiquidity);
        approveUSDT(providerAddress, address(untron), initialLiquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(initialLiquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Capture the ProviderUpdated event
        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, reducedLiquidity, rate, minOrderSize, minDeposit, receivers);

        // When: The provider decreases their liquidity
        vm.startPrank(providerAddress);
        untron.setProvider(reducedLiquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify provider's liquidity is updated
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.liquidity, reducedLiquidity, "Provider's liquidity should be decreased");

        // Verify USDT transferred back to the provider
        uint256 providerBalance = usdt.balanceOf(providerAddress);
        assertEq(providerBalance, liquidityToWithdraw, "Provider should receive the withdrawn liquidity");

        // Verify contract's USDT balance decreased
        uint256 expectedContractBalance = reducedLiquidity;
        uint256 contractBalance = usdt.balanceOf(address(untron));
        assertEq(contractBalance, expectedContractBalance, "Contract's USDT balance should reflect reduced liquidity");
    }

    /// @notice Test for updating provider's receivers
    function test_setProvider_UpdateReceivers() public {
        // Given: An existing provider with initial receivers
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory initialReceivers = new bytes21[](2);
        initialReceivers[0] = addressToBytes21(vm.addr(200));
        initialReceivers[1] = addressToBytes21(vm.addr(201));

        // Initial setup
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, initialReceivers);
        vm.stopPrank();

        // New receivers to update
        bytes21[] memory newReceivers = new bytes21[](2);
        newReceivers[0] = addressToBytes21(vm.addr(202));
        newReceivers[1] = addressToBytes21(vm.addr(203));

        // Capture the ProviderUpdated event
        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, liquidity, rate, minOrderSize, minDeposit, newReceivers);

        // When: The provider updates their receivers
        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, newReceivers);
        vm.stopPrank();

        // Then: Verify provider's receivers are updated
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.receivers.length, newReceivers.length, "Provider should have updated number of receivers");
        for (uint256 i = 0; i < newReceivers.length; i++) {
            assertEq(provider.receivers[i], newReceivers[i], "Provider's receiver should be updated correctly");
            address receiverOwner = untron.receiverOwners(newReceivers[i]);
            assertEq(receiverOwner, providerAddress, "New receiver should be owned by the provider");
        }

        // Verify old receivers are not part of the provider's receivers list
        for (uint256 i = 0; i < provider.receivers.length; i++) {
            bytes21 receiver = provider.receivers[i];
            for (uint256 j = 0; j < initialReceivers.length; j++) {
                assertNotEq(receiver, initialReceivers[j], "Old receiver should not be part of the updated receivers");
            }
        }

        // TODO: See if it is correct to overwrite receivers and that they should not be part of providers.receivers but be part of receiverOwners
    }

    /// @notice Test for updating rate and order parameters
    function test_setProvider_UpdateRateAndOrderParameters() public {
        // Given: An existing provider
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 initialRate = 1e6;
        uint256 initialMinOrderSize = 100e6;
        uint256 initialMinDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](1);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Initial setup
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, initialRate, initialMinOrderSize, initialMinDeposit, receivers);
        vm.stopPrank();

        // New parameters
        uint256 newRate = 2e6;
        uint256 newMinOrderSize = 200e6;
        uint256 newMinDeposit = 20e6;

        // Capture the ProviderUpdated event
        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, liquidity, newRate, newMinOrderSize, newMinDeposit, receivers);

        // When: The provider updates their rate and order parameters
        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, newRate, newMinOrderSize, newMinDeposit, receivers);
        vm.stopPrank();

        // Then: Verify provider's parameters are updated
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.rate, newRate, "Provider's rate should be updated");
        assertEq(provider.minOrderSize, newMinOrderSize, "Provider's minOrderSize should be updated");
        assertEq(provider.minDeposit, newMinDeposit, "Provider's minDeposit should be updated");
    }

    /// @notice Test for reverting if minDeposit > minOrderSize
    function test_setProvider_RevertIf_MinDepositGreaterThanMinOrderSize() public {
        // Given: A provider attempting to set minDeposit greater than minOrderSize
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 200e6; // Greater than minOrderSize
        bytes21[] memory receivers = new bytes21[](1);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Mint and approve USDT to the provider
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        // When: The provider attempts to set invalid parameters
        vm.startPrank(providerAddress);
        vm.expectRevert("Min deposit is greater than min order size");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();
    }

    /// @notice Test for reverting if receiver is busy with non-expired order
    function test_setProvider_RevertIf_ReceiverBusyWithNonExpiredOrder() public {
        // Given: A receiver that is busy with a non-expired order
        (address busyReceiverOwner, bytes21[] memory busyReceivers) = addProviderWithDefaultParams(1);
        addOrderWithDefaultParams(busyReceivers[0]);
        createContext();    

        // When: The provider attempts to set receivers and fails
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory newReceivers = new bytes21[](1);
        newReceivers[0] = addressToBytes21(vm.addr(201));

        // Mint and approve USDT to the provider
        mintUSDT(busyReceiverOwner, liquidity);
        approveUSDT(busyReceiverOwner, address(untron), liquidity);

        vm.startPrank(busyReceiverOwner);
        vm.expectRevert("One of the current receivers is busy with an unexpired order");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, newReceivers);
        vm.stopPrank();
    }

    /// @notice Test for reverting if receiver is owned by another provider
    function test_setProvider_RevertIf_ReceiverOwnedByAnotherProvider() public {
        // Given: A receiver owned by another provider
        address providerAddress1 = vm.addr(100);
        address providerAddress2 = vm.addr(101);
        bytes21 sharedReceiver = addressToBytes21(vm.addr(200));

        // First provider sets up and owns the receiver
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers1 = new bytes21[](1);
        receivers1[0] = sharedReceiver;

        mintUSDT(providerAddress1, liquidity);
        approveUSDT(providerAddress1, address(untron), liquidity);

        vm.startPrank(providerAddress1);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers1);
        vm.stopPrank();

        // Second provider attempts to assign the same receiver
        bytes21[] memory receivers2 = new bytes21[](1);
        receivers2[0] = sharedReceiver;

        mintUSDT(providerAddress2, liquidity);
        approveUSDT(providerAddress2, address(untron), liquidity);

        // When: The second provider attempts to set the same receiver
        vm.startPrank(providerAddress2);
        vm.expectRevert("Receiver is already owned by another provider");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers2);
        vm.stopPrank();
    }

    /// @notice Test that a receiver cannot be assigned to multiple providers simultaneously
    function test_setProvider_RevertIf_ProviderAttemptsToUseExpiredReceiverFromAnotherProvider() public {
        // Provider1 owns the receiver
        address provider1 = vm.addr(100);
        bytes21 receiver = addressToBytes21(vm.addr(200));

        bytes21[] memory receivers1 = new bytes21[](1);
        receivers1[0] = receiver;

        mintUSDT(provider1, 1000e6);
        approveUSDT(provider1, address(untron), 1000e6);

        vm.startPrank(provider1);
        untron.setProvider(1000e6, 1e6, 10e6, 10e6, receivers1);
        vm.stopPrank();

        // Provider2 attempts to assign the same receiver
        address provider2 = vm.addr(101);
        bytes21[] memory receivers2 = new bytes21[](1);
        receivers2[0] = receiver;

        mintUSDT(provider2, 1000e6);
        approveUSDT(provider2, address(untron), 1000e6);

        vm.startPrank(provider2);
        vm.expectRevert("Receiver is already owned by another provider");
        untron.setProvider(1000e6, 1e6, 10e6, 10e6, receivers2);
        vm.stopPrank();

        // An order is created for the receiver and expired
        address orderCreator = vm.addr(777);
        mintUSDT(orderCreator, untron.requiredCollateral() + 10e6);
        approveUSDT(orderCreator, address(untron), untron.requiredCollateral() + 10e6);
        vm.startPrank(orderCreator);
        untron.createOrder(provider1, receiver, 10e6, 1e6, getTransferDetails(orderCreator, true));
        vm.stopPrank();
        expireOrder();

        // Provider2 fails to assign the receiver
        vm.startPrank(provider2);
        vm.expectRevert("Receiver is already owned by another provider");
        untron.setProvider(1000e6, 1e6, 10e6, 10e6, receivers2);
        vm.stopPrank();
    }

    /// @notice Test for setting zero liquidity
    function testSetProvider_RevertIf_ZeroLiquidity() public {
      // Given: A provider with existing liquidity who wants to withdraw all funds
    address providerAddress = vm.addr(100);
    uint256 initialLiquidity = 1000e6;
    uint256 rate = 1e6;
    uint256 minOrderSize = 100e6;
    uint256 minDeposit = 10e6;
    bytes21[] memory receivers = new bytes21[](1);
    receivers[0] = addressToBytes21(vm.addr(200));

    // Initial setup
    mintUSDT(providerAddress, initialLiquidity);
    approveUSDT(providerAddress, address(untron), initialLiquidity);

    vm.startPrank(providerAddress);
    untron.setProvider(initialLiquidity, rate, minOrderSize, minDeposit, receivers);
    vm.stopPrank();

    // When: The provider tries to set liquidity to zero (expecting a revert)
    vm.startPrank(providerAddress);
    vm.expectRevert(); 
    untron.setProvider(0, rate, minOrderSize, minDeposit, receivers);
    vm.stopPrank();

    // Then: Verify provider's liquidity remains unchanged
    IUntronCore.Provider memory provider = untron.providers(providerAddress);
    assertEq(provider.liquidity, initialLiquidity, "Provider's liquidity should remain unchanged");
    
    // Verify the provider still has their initial balance
    uint256 providerBalance = usdt.balanceOf(providerAddress);
    assertEq(providerBalance, 0, "Provider should still have their initial liquidity");

    // Verify contract balance
    uint256 contractBalance = usdt.balanceOf(address(untron));
    assertEq(contractBalance, initialLiquidity, "Contract's USDT balance should remain the same");
    }

    /// @notice Test for setting zero receivers
    function test_setProvider_ZeroReceivers() public {
        // Given: A provider with existing receivers who wants to remove all receivers
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory initialReceivers = new bytes21[](2);
        initialReceivers[0] = addressToBytes21(vm.addr(200));
        initialReceivers[1] = addressToBytes21(vm.addr(201));

        // Initial setup
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, initialReceivers);
        vm.stopPrank();

        // When: The provider sets receivers to an empty array
        bytes21[] memory emptyReceivers = new bytes21[](0);

        vm.expectEmit(true, true, true, true);
        emit ProviderUpdated(providerAddress, liquidity, rate, minOrderSize, minDeposit, emptyReceivers);

        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, emptyReceivers);
        vm.stopPrank();

        // Then: Verify provider's receivers list is empty
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.receivers.length, 0, "Provider's receivers list should be empty");

        // TODO: See if it is correct to overwrite receivers and that they should not be part of providers.receivers but be part of receiverOwners
    }

    /// @notice Test for setting receiver that is busy due to an expired order
    function test_setProvider_AssignBusyReceiverFromExpiredOrder() public {
        // Given: A receiver that is busy due to an expired order
        address orderCreator = vm.addr(777);
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](1);
        bytes21 busyReceiver = addressToBytes21(vm.addr(200));
        receivers[0] = busyReceiver;

        // Step 1: Set up initial provider and create an order to make the receiver busy
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        vm.startPrank(providerAddress);
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Create an order to make the receiver busy
        mintUSDT(orderCreator, 1000e6);
        approveUSDT(orderCreator, address(untron), 1000e6);
        vm.startPrank(orderCreator);
        uint256 orderSize = 200e6;
        IUntronTransfers.Transfer memory transfer = IUntronTransfers.Transfer({
            directTransfer: true,
            data: abi.encode(orderCreator)
        });
        untron.createOrder(providerAddress, busyReceiver, orderSize, rate, transfer);
        vm.stopPrank();

        // Step 2: Fast forward time to expire the order
        expireOrder();

        // When: The provider tries to assign the busy receiver (from expired order)
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);
        
        vm.startPrank(providerAddress);
       
        vm.expectRevert("One of the current receivers is busy with an unexpired order");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
  
        vm.stopPrank();

   // Then: Verify that the receiver is not available for the provider
    IUntronCore.Provider memory provider = untron.providers(providerAddress);
    
    // Verify total number of receivers
    assertEq(
        provider.receivers.length, 
        receivers.length, 
        "Provider should have same number of receivers"
    );

    // Check if the receiver is in the provider's list
    bool receiverFound = false;
    
    for (uint i = 0; i < provider.receivers.length; i++) {
        if (provider.receivers[i] == busyReceiver) {
            receiverFound = true;
            break;
        }
    }
    
   
    assertTrue(
        receiverFound, 
        "Receiver should be available for the provider"
    );

    // Verify the receiver ownership
    address receiverOwner = untron.receiverOwners(busyReceiver);
    assertEq(
        receiverOwner, 
        providerAddress,  // Changed from address(0) to providerAddress
        "Receiver should be owned by the provider"
    );

    // Verify receiver busy status
    bytes32 storedOrderId = untron.isReceiverBusy(busyReceiver);
    assert(storedOrderId != bytes32(0));
    }

   
    /// @notice Test for setting provider with zero min deposit
    function testSetProvider_RevertIf_ZeroMinDeposit() public {
        // Given: A provider address and parameters
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 0; // Set minDeposit to zero
        bytes21[] memory receivers = new bytes21[](2);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Mint and approve USDT
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        // Store initial provider state
        IUntronCore.Provider memory initialProvider = untron.providers(providerAddress);
        
        // Start the prank as the provider
        vm.startPrank(providerAddress);
        
        // When: Attempting to set provider
        vm.expectRevert("Parameters should be greater than zero");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify that the provider's state remains unchanged
        IUntronCore.Provider memory finalProvider = untron.providers(providerAddress);
        assertEq(finalProvider.liquidity, initialProvider.liquidity, "Provider's liquidity should remain unchanged");
        assertEq(finalProvider.rate, initialProvider.rate, "Provider's rate should remain unchanged");
        assertEq(finalProvider.minOrderSize, initialProvider.minOrderSize, "Provider's minOrderSize should remain unchanged");
        assertEq(finalProvider.minDeposit, initialProvider.minDeposit, "Provider's minDeposit should remain unchanged");
    }

    /// @notice Test for setting provider with zero min order size
    function testSetProvider_RevertIf_ZeroMinOrderSize() public {
        // Given: A provider address and parameters
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 1e6;
        uint256 minOrderSize = 0; // Set minOrderSize to zero
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](2);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Mint and approve USDT
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        // Store initial provider state
        IUntronCore.Provider memory initialProvider = untron.providers(providerAddress);
        
        // Start the prank as the provider
        vm.startPrank(providerAddress);
        
        // When: Attempting to set provider
        vm.expectRevert("Parameters should be greater than zero");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify that the provider's state remains unchanged
        IUntronCore.Provider memory finalProvider = untron.providers(providerAddress);
        assertEq(finalProvider.liquidity, initialProvider.liquidity, "Provider's liquidity should remain unchanged");
        assertEq(finalProvider.rate, initialProvider.rate, "Provider's rate should remain unchanged");
        assertEq(finalProvider.minOrderSize, initialProvider.minOrderSize, "Provider's minOrderSize should remain unchanged");
        assertEq(finalProvider.minDeposit, initialProvider.minDeposit, "Provider's minDeposit should remain unchanged");
    }

    /// @notice Test for setting provider with zero rate
    function testSetProvider_RevertIf_ZeroRate() public {
        // Given: A provider address and parameters
        address providerAddress = vm.addr(100);
        uint256 liquidity = 1000e6;
        uint256 rate = 0; // Set rate to zero
        uint256 minOrderSize = 100e6;
        uint256 minDeposit = 10e6;
        bytes21[] memory receivers = new bytes21[](2);
        receivers[0] = addressToBytes21(vm.addr(200));

        // Mint and approve USDT
        mintUSDT(providerAddress, liquidity);
        approveUSDT(providerAddress, address(untron), liquidity);

        // Store initial provider state
        IUntronCore.Provider memory initialProvider = untron.providers(providerAddress);
        
        // Start the prank as the provider
        vm.startPrank(providerAddress);
        
        // When: Attempting to set provider
        vm.expectRevert("Parameters should be greater than zero");
        untron.setProvider(liquidity, rate, minOrderSize, minDeposit, receivers);
        vm.stopPrank();

        // Then: Verify that the provider's state remains unchanged
        IUntronCore.Provider memory finalProvider = untron.providers(providerAddress);
        assertEq(finalProvider.liquidity, initialProvider.liquidity, "Provider's liquidity should remain unchanged");
        assertEq(finalProvider.rate, initialProvider.rate, "Provider's rate should remain unchanged");
        assertEq(finalProvider.minOrderSize, initialProvider.minOrderSize, "Provider's minOrderSize should remain unchanged");
        assertEq(finalProvider.minDeposit, initialProvider.minDeposit, "Provider's minDeposit should remain unchanged");
    }



    /// @notice Invariant test: Provider state consistency after multiple updates
    function test_invariant_setProvider_ProviderStateConsistency() public {
        // This test would require setting up a stateful testing environment
        // where multiple random `setProvider` calls are made, and after each,
        // we check that the provider's state remains consistent.

        // For simplicity, we'll simulate a few updates here

        address providerAddress = vm.addr(100);

        // Initial setup
        uint256 initialLiquidity = 1000e6;
        mintUSDT(providerAddress, initialLiquidity);
        approveUSDT(providerAddress, address(untron), initialLiquidity);

        bytes21[] memory receivers = new bytes21[](1);
        receivers[0] = addressToBytes21(vm.addr(200));

        vm.startPrank(providerAddress);
        untron.setProvider(initialLiquidity, 1e6, 100e6, 10e6, receivers);
        vm.stopPrank();

        // Update 1
        uint256 newLiquidity = 1500e6;
        mintUSDT(providerAddress, 500e6);
        approveUSDT(providerAddress, address(untron), 500e6);

        vm.startPrank(providerAddress);
        untron.setProvider(newLiquidity, 1.5e6, 150e6, 15e6, receivers);
        vm.stopPrank();

        // Update 2
        uint256 reducedLiquidity = 1200e6;
        vm.startPrank(providerAddress);
        untron.setProvider(reducedLiquidity, 1.2e6, 120e6, 12e6, receivers);
        vm.stopPrank();

        // Verify provider's state consistency
        IUntronCore.Provider memory provider = untron.providers(providerAddress);
        assertEq(provider.liquidity, reducedLiquidity, "Provider's liquidity should be consistent");
        assertEq(provider.rate, 1.2e6, "Provider's rate should be consistent");
        assertEq(provider.minOrderSize, 120e6, "Provider's minOrderSize should be consistent");
        assertEq(provider.minDeposit, 12e6, "Provider's minDeposit should be consistent");
    }
}
