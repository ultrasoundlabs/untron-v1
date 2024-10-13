// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UntronCore.sol";
import "./mocks/MockLifi.sol";
import "@sp1-contracts/SP1MockVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract UntronZKTest is Test {
    UntronCore untronZKImplementation;
    UntronCore untronZK;
    MockLifi lifi;
    SP1MockVerifier sp1Verifier;
    MockUSDT usdt;

    address admin = address(1);

    constructor() {
        vm.warp(1725527575); // the time i did this test at
    }

    function setUp() public {
        vm.startPrank(admin);

        lifi = new MockLifi();
        sp1Verifier = new SP1MockVerifier();
        usdt = new MockUSDT();

        bytes memory state = "hello 123";

        // Use UntronCore since UntronFees is abstract
        untronZKImplementation = new UntronCore();
        // Prepare the initialization data
        bytes memory initData = abi.encodeWithSelector(UntronCore.initialize.selector, state);

        // Deploy the proxy, pointing to the implementation and passing the init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(untronZKImplementation), initData);
        untronZK = UntronCore(address(proxy));

        vm.stopPrank();
    }

    function test_setUp() public view {
        // Check role
        assertEq(untronZK.owner(), admin);
    }

    function test_setUntronZKVariables_SetVariables() public {
        vm.startPrank(admin);

        address trustedRelayer = address(420);
        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        untronZK.setZKVariables(trustedRelayer, verifier, vkey);

        assertEq(untronZK.verifier(), verifier);
        assertEq(untronZK.vkey(), vkey);

        vm.stopPrank();
    }

    function test_setUntronZKVariables_RevertIf_NotUpgraderRole() public {
        address trustedRelayer = address(420);
        address verifier = address(sp1Verifier);
        bytes32 vkey = bytes32(uint256(1));

        vm.expectRevert();
        untronZK.setZKVariables(trustedRelayer, verifier, vkey);
    }
}
