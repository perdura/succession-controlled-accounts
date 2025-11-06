// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract SimpleSuccessionRegistryTest is BaseTest {
    address public registry;

    function setUp() public override {
        super.setUp();

        vm.startPrank(alice);
        nft.mint();
        registry = registryFactory.createRegistry();
        vm.stopPrank();
    }

    // ============ Initialization ============

    function test_RegistryInitialization() public view {
        SimpleSuccessionRegistry reg = SimpleSuccessionRegistry(registry);
        assertEq(reg.owner(), alice);
        assertEq(address(reg.controllerNFT()), address(nft));
    }

    function test_RevertWhen_InitializingImplementation() public {
        vm.expectRevert();
        registryImpl.initialize(alice, address(nft), address(registryFactory));
    }

    function test_OnlyFactoryCanInitialize() public {
        address clone = Clones.clone(address(registryImpl));

        vm.prank(address(registryFactory));
        SimpleSuccessionRegistry(clone).initialize(alice, address(nft), address(registryFactory));

        assertEq(SimpleSuccessionRegistry(clone).owner(), alice);
    }

    function test_RevertWhen_ReinitializingClone() public {
        vm.prank(address(registryFactory));
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).initialize(bob, address(nft), address(registryFactory));
    }

    // ============ Policy Configuration ============

    function test_setupSimplePolicy_SixMonths() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        SimpleSuccessionRegistry.Policy memory policy = SimpleSuccessionRegistry(registry).getPolicy();
        assertEq(policy.beneficiary, bob);
        assertEq(uint256(policy.waitPeriod), uint256(SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS));
        assertTrue(policy.configured);
    }

    function test_setupSimplePolicy_OneYear() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        SimpleSuccessionRegistry.Policy memory policy = SimpleSuccessionRegistry(registry).getPolicy();
        assertEq(uint256(policy.waitPeriod), uint256(SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR));
    }

    function test_RevertWhen_AlreadyConfigured() public {
        vm.startPrank(alice);

        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.expectRevert(SimpleSuccessionRegistry.AlreadyConfigured.selector);
        SimpleSuccessionRegistry(registry)
            .setupSimplePolicy(charlie, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        vm.stopPrank();
    }

    function test_RevertWhen_ZeroBeneficiary() public {
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.ZeroAddress.selector);
        SimpleSuccessionRegistry(registry)
            .setupSimplePolicy(address(0), SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
    }

    function test_RevertWhen_NonOwnerConfigures() public {
        vm.prank(bob);
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
    }

    // ============ Check-In ============

    function test_CheckIn() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        uint64 initialCheckIn = SimpleSuccessionRegistry(registry).getPolicy().lastCheckIn;

        vm.warp(block.timestamp + 8 days);

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();

        uint64 newCheckIn = SimpleSuccessionRegistry(registry).getPolicy().lastCheckIn;
        assertGt(newCheckIn, initialCheckIn);
    }

    function test_CheckInResetsSuccessionTimer() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 179 days);

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();

        // Even after 2 more days (total 181 from original), Bob still can't claim
        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Must wait full period from last check-in
        vm.warp(block.timestamp + 180 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
        assertEq(nft.ownerOf(1), bob);
    }

    function test_RevertWhen_CheckInTooSoon() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.CheckInTooSoon.selector);
        SimpleSuccessionRegistry(registry).checkIn();

        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.CheckInTooSoon.selector);
        SimpleSuccessionRegistry(registry).checkIn();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();
    }

    function test_RevertWhen_NotOwnerChecksIn() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 8 days);

        vm.prank(bob);
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).checkIn();
    }

    function test_RevertWhen_CheckInNotConfigured() public {
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.NotConfigured.selector);
        SimpleSuccessionRegistry(registry).checkIn();
    }

    // ============ Estate Transfer ============

    function test_executeSuccession_SixMonths() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        assertEq(nft.ownerOf(1), bob);
    }

    function test_executeSuccession_OneYear() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        vm.warp(block.timestamp + 366 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
        assertEq(nft.ownerOf(1), bob);
    }

    function test_RevertWhen_TooEarlyTransfer() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 179 days);

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
    }

    function test_RevertWhen_NotBeneficiary() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(charlie);
        vm.expectRevert(SimpleSuccessionRegistry.Unauthorized.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();
    }

    function test_RevertWhen_ExecuteTransferNotConfigured() public {
        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.NotConfigured.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();
    }

    // ============ Beneficiary Updates ============

    function test_UpdateBeneficiary() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).updateBeneficiary(charlie);

        SimpleSuccessionRegistry.Policy memory policy = SimpleSuccessionRegistry(registry).getPolicy();
        assertEq(policy.beneficiary, charlie);
    }

    function test_BeneficiaryUpdateChangesWhoCanClaim() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).updateBeneficiary(charlie);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.Unauthorized.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        vm.prank(charlie);
        SimpleSuccessionRegistry(registry).executeSuccession();
        assertEq(nft.getCurrentController(alice), charlie);
    }

    function test_RevertWhen_NotOwnerUpdatesBeneficiary() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.prank(bob);
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).updateBeneficiary(charlie);
    }

    function test_RevertWhen_UpdateBeneficiaryNotConfigured() public {
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.NotConfigured.selector);
        SimpleSuccessionRegistry(registry).updateBeneficiary(bob);
    }

    function test_RevertWhen_UpdateBeneficiaryToZero() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.ZeroAddress.selector);
        SimpleSuccessionRegistry(registry).updateBeneficiary(address(0));
    }

    // ============ Capacity Limits ============

    function test_PartialTransferWhenBeneficiaryAtCapacity() public {
        uint256 maxTokens = nft.MAX_INHERITED_TOKENS();

        vm.prank(bob);
        nft.mint();

        for (uint256 i = 0; i < maxTokens - 1; i++) {
            vm.warp(1);
            address user = makeAddr(string.concat("user", vm.toString(i)));
            vm.deal(user, 10 ether);

            vm.startPrank(user);
            nft.mint();
            address userRegistry = registryFactory.createRegistry();
            SimpleSuccessionRegistry(userRegistry)
                .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
            vm.stopPrank();

            vm.warp(block.timestamp + 180 days);
            vm.prank(bob);
            SimpleSuccessionRegistry(userRegistry).executeSuccession();
        }

        assertEq(nft.getUserOwnedTokens(bob).length, maxTokens);

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SimpleSuccessionRegistry.InsufficientSpace.selector, maxTokens, 1, 0));
        SimpleSuccessionRegistry(registry).executeSuccession();
    }

    // ============ View Functions ============

    function test_GetStatus_NotConfigured() public view {
        (string memory mode, address beneficiary, uint256 daysUntilClaimable, bool isClaimable) =
            SimpleSuccessionRegistry(registry).getStatus();

        assertEq(mode, "Not Configured");
        assertEq(beneficiary, address(0));
        assertEq(daysUntilClaimable, 0);
        assertFalse(isClaimable);
    }

    function test_GetStatus_Configured() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        (string memory mode, address beneficiary, uint256 daysUntilClaimable, bool isClaimable) =
            SimpleSuccessionRegistry(registry).getStatus();

        assertEq(mode, "Simple");
        assertEq(beneficiary, bob);
        assertEq(daysUntilClaimable, 180);
        assertFalse(isClaimable);
    }

    function test_GetStatus_Claimable() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        (,, uint256 daysUntilClaimable, bool isClaimable) = SimpleSuccessionRegistry(registry).getStatus();

        assertEq(daysUntilClaimable, 0);
        assertTrue(isClaimable);
    }

    function test_GetPolicy() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        SimpleSuccessionRegistry.Policy memory policy = SimpleSuccessionRegistry(registry).getPolicy();

        assertEq(policy.beneficiary, bob);
        assertEq(uint256(policy.waitPeriod), uint256(SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR));
        assertTrue(policy.configured);
    }

    function test_CanExecuteSuccession_BeforeWaitingPeriod() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        assertFalse(SimpleSuccessionRegistry(registry).canExecuteSuccession());
    }

    function test_CanExecuteSuccession_AfterWaitingPeriod() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);
        assertTrue(SimpleSuccessionRegistry(registry).canExecuteSuccession());
    }

    function test_GetBeneficiary() public {
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        assertEq(SimpleSuccessionRegistry(registry).getBeneficiary(), bob);
    }
}
