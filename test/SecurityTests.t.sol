// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

/**
 * @title SecurityTests
 * @notice Tests security protections and attack resistance
 * @dev All tests verify that security measures WORK correctly
 */
contract SecurityTests is BaseTest {
    // ============ INITIALIZATION PROTECTION TESTS ============

    function test_DirectCloneInitializationCreatesUselessAccount() public {
        // Deploy a clone outside of factory (simulating attack vector)
        address clone = Clones.clone(address(accountImpl));

        // Attacker can initialize by passing their own address as factory
        vm.prank(attacker);
        SimpleAccount(payable(clone))
            .initialize(
                attacker,
                address(nft),
                attacker // Attacker passes self as factory
            );

        // Initialization succeeds, but the account is useless because:
        // 1. Attacker doesn't have a Controller NFT
        // 2. Even if they mint one, the factory doesn't track this clone
        // 3. The clone isn't authorized in any way

        // Verify attacker owns the clone
        assertEq(SimpleAccount(payable(clone)).getOriginalHolder(), attacker);

        // But it's useless - attacker has no Controller NFT
        assertEq(nft.hasMinted(attacker), false);

        // Factory doesn't know about this clone
        address[] memory attackerAccounts = accountFactory.getUserAccounts(attacker);
        assertEq(attackerAccounts.length, 0);

        // The proper way: use factory.createAccount()
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address properAccount = accountFactory.createAccount();

        // Factory tracks this account
        address[] memory aliceAccounts = accountFactory.getUserAccounts(alice);
        assertEq(aliceAccounts.length, 1);
        assertEq(aliceAccounts[0], properAccount);
    }

    function test_FactoryPreventsUnauthorizedInitialization() public {
        // This is what actually happens - factory deploys and initializes atomically
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        // Registry is already initialized by factory
        // Attacker can't do anything with it
        vm.prank(attacker);
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).initialize(attacker, address(nft), attacker);
    }

    function test_CloneCannotBeReinitialized() public {
        // Create legitimate account
        vm.startPrank(alice);
        nft.mint();
        address account = accountFactory.createAccount();
        vm.stopPrank();

        // Attempt to reinitialize - should FAIL
        vm.prank(attacker);
        vm.expectRevert();
        SimpleAccount(payable(account)).initialize(attacker, address(nft), attacker);

        // Even factory cannot reinitialize
        vm.prank(address(accountFactory));
        vm.expectRevert();
        SimpleAccount(payable(account)).initialize(bob, address(nft), address(accountFactory));
    }

    function test_ImplementationContractCannotBeInitialized() public {
        // Implementation should have initializers disabled
        vm.expectRevert();
        accountImpl.initialize(alice, address(nft), address(accountFactory));

        vm.expectRevert();
        registryImpl.initialize(alice, address(nft), address(registryFactory));
    }

    // ============ REENTRANCY PROTECTION TESTS ============

    function test_EstateTransferProtectedFromReentrancy() public {
        // Setup estate with malicious beneficiary
        ReentrantBeneficiary maliciousBob = new ReentrantBeneficiary();

        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry)
            .setupSimplePolicy(address(maliciousBob), SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Set up reentrancy attack
        maliciousBob.setTarget(registry);

        // Execute after waiting period
        vm.warp(block.timestamp + 181 days);

        // Attack executes but reentrancy is blocked
        vm.prank(address(maliciousBob));
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Verify reentrancy was blocked (only 1 execution, not 2)
        assertEq(maliciousBob.attackExecuted(), 1, "Reentrancy should be blocked");
    }

    function test_AssetSweepProtectedFromReentrancy() public {
        vm.startPrank(alice);
        nft.mint();
        address account = accountFactory.createAccount();
        vm.stopPrank();

        // Fund account
        vm.deal(account, 10 ether);

        // Create malicious receiver
        ReentrantReceiver maliciousReceiver = new ReentrantReceiver(account);

        // Attempt sweep to malicious receiver
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(address(maliciousReceiver), 5 ether);

        // Verify only one transfer occurred
        assertEq(address(maliciousReceiver).balance, 5 ether);
        assertEq(address(account).balance, 5 ether);
    }

    // ============ AUTHORIZATION TESTS ============

    function test_OnlyAuthorizedRegistriesCanTransferNFT() public {
        vm.prank(alice);
        nft.mint();

        address unauthorizedRegistry = makeAddr("unauthorizedRegistry");

        // Unauthorized registry cannot transfer
        vm.prank(unauthorizedRegistry);
        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.safeTransferFrom(alice, bob, 1);
    }

    function test_TrustedFactoryCanAuthorizeRegistries() public {
        vm.prank(alice);
        nft.mint();

        // Create registry through trusted factory - auto-authorized
        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        // Verify authorization
        assertTrue(nft.isAuthorizedRegistry(alice, registry));
    }

    function test_UntrustedFactoryCannotAuthorizeRegistries() public {
        address untrustedFactory = makeAddr("untrustedFactory");
        address fakeRegistry = makeAddr("fakeRegistry");

        vm.prank(alice);
        nft.mint();

        // Untrusted factory cannot authorize
        vm.prank(untrustedFactory);
        vm.expectRevert(ControllerNFT.NotTrustedFactory.selector);
        nft.authorizeRegistry(alice, fakeRegistry);
    }

    function test_FactoryCannotAuthorizeWrongRegistry() public {
        vm.prank(alice);
        nft.mint();

        address wrongRegistry = makeAddr("wrongRegistry");

        // Factory tries to authorize registry that doesn't belong to alice
        vm.prank(address(registryFactory));
        vm.expectRevert(ControllerNFT.NotAuthorized.selector);
        nft.authorizeRegistry(alice, wrongRegistry);
    }

    // ============ ACCESS CONTROL TESTS ============

    function test_OnlyCurrentControllerCanSweepAssets() public {
        vm.startPrank(alice);
        nft.mint();
        address account = accountFactory.createAccount();
        vm.stopPrank();

        vm.deal(account, 10 ether);

        // Attacker cannot sweep
        vm.prank(attacker);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepNative(attacker, 5 ether);

        // Alice can sweep
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, 5 ether);
        assertEq(alice.balance, 105 ether);
    }

    function test_OnlyBeneficiaryCanexecuteSuccession() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        // Attacker cannot execute
        vm.prank(attacker);
        vm.expectRevert(SimpleSuccessionRegistry.Unauthorized.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Bob (beneficiary) can execute
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
    }

    function test_OnlyOwnerCanCheckIn() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 8 days);

        // Bob cannot check in (not owner)
        vm.prank(bob);
        vm.expectRevert();
        SimpleSuccessionRegistry(registry).checkIn();

        // Alice can check in
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();
    }

    // ============ INHERITANCE LIMIT PROTECTION ============

    function test_InheritanceLimitPreventsStorageDOS() public {
        uint256 maxTokens = nft.MAX_INHERITED_TOKENS();

        // Bob mints his own NFT
        vm.prank(bob);
        nft.mint();

        // Create users who will all transfer to Bob
        for (uint256 i = 0; i < maxTokens; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(user, 10 ether);

            vm.prank(user);
            nft.mint();

            vm.prank(user);
            address reg = registryFactory.createRegistry();

            vm.prank(user);
            SimpleSuccessionRegistry(reg).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        }

        vm.warp(block.timestamp + 181 days);

        // Bob can receive up to MAX_INHERITED_TOKENS - 1 (he has his own)
        for (uint256 i = 0; i < maxTokens - 1; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            address userRegistry = registryFactory.userRegistry(user);

            vm.prank(bob);
            SimpleSuccessionRegistry(userRegistry).executeSuccession();
        }

        // Next transfer should fail (would exceed limit)
        assertEq(nft.getUserOwnedTokens(bob).length, maxTokens);

        // Next transfer should fail (would exceed limit)
        address lastUser = makeAddr(string(abi.encodePacked("user", maxTokens - 1)));
        address lastRegistry = registryFactory.userRegistry(lastUser);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SimpleSuccessionRegistry.InsufficientSpace.selector, maxTokens, 1, 0));
        SimpleSuccessionRegistry(lastRegistry).executeSuccession();
    }

    // ============ SPAM PROTECTION TESTS ============

    function test_BeneficiaryCanBurnUnwantedTokens() public {
        // Setup: Bob inherits Charlie's token
        vm.prank(charlie);
        nft.mint();
        uint256 charlieTokenId = nft.originalTokenId(charlie);
        vm.prank(charlie);
        address charlieRegistry = registryFactory.createRegistry();

        vm.prank(charlie);
        SimpleSuccessionRegistry(charlieRegistry)
            .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(charlieRegistry).executeSuccession();

        // Bob owns Charlie's token
        assertEq(nft.ownerOf(charlieTokenId), bob);

        // Bob burns the unwanted token directly
        vm.prank(bob);
        nft.burn(charlieTokenId);

        // Token is burned
        vm.expectRevert();
        nft.ownerOf(charlieTokenId);
    }

    // ============ TIMING ATTACK PREVENTION ============

    function test_MinimumCheckInIntervalPreventSpam() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Immediate check-in should fail
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.CheckInTooSoon.selector);
        SimpleSuccessionRegistry(registry).checkIn();

        // After 6 days should still fail
        vm.warp(block.timestamp + 6 days);
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.CheckInTooSoon.selector);
        SimpleSuccessionRegistry(registry).checkIn();

        // After 8 days should succeed
        vm.warp(block.timestamp + 2 days);
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();
    }

    function test_WaitPeriodPreventsPrematureClaims() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Just before 180 days
        vm.warp(block.timestamp + 179 days);
        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // After 180 days
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
    }
}

// ============ ATTACK CONTRACTS FOR TESTING ============

contract ReentrantBeneficiary {
    address public target;
    uint256 public attackExecuted;

    function setTarget(address _target) external {
        target = _target;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attackExecuted == 0) {
            attackExecuted++;
            // Try to reenter
            try SimpleSuccessionRegistry(target).executeSuccession() {
                attackExecuted++; // Should never reach here
            } catch {
                // Reentrancy blocked - expected
            }
        }
        return this.onERC721Received.selector;
    }
}

contract ReentrantReceiver {
    address public targetAccount;
    uint256 public attackExecuted;

    constructor(address _targetAccount) {
        targetAccount = _targetAccount;
    }

    receive() external payable {
        if (attackExecuted == 0) {
            attackExecuted++;
            // Try to reenter sweep
            try SimpleAccount(payable(targetAccount)).sweepAllNative() {
                attackExecuted++; // Should never reach here
            } catch {
                // Reentrancy blocked - expected
            }
        }
    }
}
