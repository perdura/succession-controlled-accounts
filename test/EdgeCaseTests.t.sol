// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

/**
 * @title EdgeCaseTests
 * @notice Tests edge cases, boundary conditions, and unusual scenarios
 * @dev Non-redundant edge cases only - basic functionality tested elsewhere
 */
contract EdgeCaseTests is BaseTest {
    // ============ EMPTY/ZERO VALUE OPERATIONS ============

    function test_EmptyAccountSuccession() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Create account but don't fund it
        address account = accountFactory.createAccount();
        vm.stopPrank();

        // Execute succession with empty account
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Bob controls empty account
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), bob);
        assertEq(SimpleAccount(payable(account)).getNativeBalance(), 0);
    }

    // ============ MAXIMUM LIMITS ============

    function test_MaximumAccountsPerUser() public {
        vm.startPrank(alice);
        nft.mint();

        uint256 maxAccounts = accountFactory.getMaxAccountsPerUser();

        // Create maximum accounts
        for (uint256 i = 0; i < maxAccounts; i++) {
            accountFactory.createAccount();
        }

        // One more should fail
        vm.expectRevert(AccountFactory.AccountLimitExceeded.selector);
        accountFactory.createAccount();

        vm.stopPrank();
    }

    function test_SequentialTokenIdIncrement() public {
        uint256 currentId = nft.nextTokenId();

        // Mint several tokens
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string.concat("user", vm.toString(i)));
            vm.prank(user);
            nft.mint();
        }

        assertEq(nft.nextTokenId(), currentId + 10);
        assertEq(nft.totalMinted(), 10);
    }

    // ============ RACE CONDITIONS ============

    function test_ConcurrentRegistryCreationPrevented() public {
        vm.prank(alice);
        nft.mint();

        // First creation succeeds
        vm.prank(alice);
        address registry1 = registryFactory.createRegistry();
        assertNotEq(registry1, address(0));

        // Second creation fails (prevents race condition)
        vm.prank(alice);
        vm.expectRevert(RegistryFactory.RegistryAlreadyExists.selector);
        registryFactory.createRegistry();
    }

    function test_RapidAccountCreationProducesUniqueAddresses() public {
        vm.startPrank(alice);
        nft.mint();

        // Create accounts rapidly
        address[] memory accounts = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            accounts[i] = accountFactory.createAccount();

            // Each should be unique
            for (uint256 j = 0; j < i; j++) {
                assertTrue(accounts[i] != accounts[j], "Duplicate account address");
            }
        }

        vm.stopPrank();
    }

    // ============ STATE TRANSITIONS ============

    function test_BeneficiaryUpdateDuringWaitingPeriod() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Wait partial period
        vm.warp(block.timestamp + 90 days);

        // Update beneficiary
        SimpleSuccessionRegistry(registry).updateBeneficiary(charlie);

        // Bob can no longer claim
        vm.warp(block.timestamp + 91 days); // Total 181 days
        vm.stopPrank();

        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.Unauthorized.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Charlie can claim after full 180 day wait after beneficiary update
        vm.warp(block.timestamp + 180 days);
        vm.prank(charlie);
        SimpleSuccessionRegistry(registry).executeSuccession();
        assertEq(nft.getCurrentController(alice), charlie);
    }

    function test_CheckInAfterWaitingPeriodResetsTimer() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Wait past succession period
        vm.warp(block.timestamp + 181 days);

        // Alice can still check in (prevents succession)
        SimpleSuccessionRegistry(registry).checkIn();
        vm.stopPrank();

        // Bob cannot execute immediately after check-in
        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Must wait another full period, warp to 180 days minus 1 second
        vm.warp(block.timestamp + 180 days - 1);
        vm.prank(bob);
        vm.expectRevert(SimpleSuccessionRegistry.ConditionsNotMet.selector);
        SimpleSuccessionRegistry(registry).executeSuccession();

        vm.warp(block.timestamp + 1);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
        assertEq(nft.getCurrentController(alice), bob);
    }

    // ============ FACTORY EDGE CASES ============

    function test_FactoryRejectsZeroImplementation() public {
        // Try to deploy factory with zero address implementation
        vm.expectRevert();
        new RegistryFactory(address(0), address(nft));

        vm.expectRevert();
        new AccountFactory(address(0), address(nft));
    }

    function test_FactoryUseAfterBurn() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        address account = accountFactory.createAccount();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        // Bob inherits
        vm.warp(block.timestamp + 181 days);
        vm.startPrank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Bob burns inherited token from Alice
        nft.burn(nft.originalTokenId(alice));
        vm.stopPrank();

        // Alice's token burned, so her account has no valid controller (address(0))
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), address(0));

        // Alice wallet compromised: attacker attempts to create registry and account
        vm.startPrank(alice);
        vm.expectRevert(RegistryFactory.NoControllerNFT.selector);
        address attackRegistry = registryFactory.createRegistry();

        vm.expectRevert(AccountFactory.NoControllerNFT.selector);
        address attackAccount = accountFactory.createAccount();
        vm.stopPrank();

        assertEq(attackRegistry, address(0));
        assertEq(attackAccount, address(0));
    }

    // ============ PAGINATION EDGE CASES ============

    function test_PaginationBoundaries() public {
        // Create exactly 10 registries
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string.concat("user", vm.toString(i)));
            vm.prank(user);
            nft.mint();
            vm.prank(user);
            registryFactory.createRegistry();
        }

        // Get first 5
        address[] memory page1 = registryFactory.getRegistriesPaginated(0, 5);
        assertEq(page1.length, 5);

        // Get next 5
        address[] memory page2 = registryFactory.getRegistriesPaginated(5, 5);
        assertEq(page2.length, 5);

        // Get beyond limit - returns empty
        address[] memory page3 = registryFactory.getRegistriesPaginated(10, 5);
        assertEq(page3.length, 0);

        // Get partial page
        address[] memory page4 = registryFactory.getRegistriesPaginated(8, 5);
        assertEq(page4.length, 2);
    }

    function test_PaginationRejectsOversizedPages() public {
        vm.expectRevert(RegistryFactory.InvalidPageSize.selector);
        registryFactory.getRegistriesPaginated(0, 1001);

        vm.expectRevert(AccountFactory.InvalidPageSize.selector);
        accountFactory.getAccountsPaginated(0, 1001);
    }

    // ============ TOKEN TRACKING AFTER BURN ============

    function test_TokenTrackingAfterBurn() public {
        vm.prank(alice);
        nft.mint();

        uint256 tokenId = nft.originalTokenId(alice);

        uint256[] memory tokensBefore = nft.getUserOwnedTokens(alice);
        assertEq(tokensBefore.length, 1);

        vm.prank(alice);
        vm.expectRevert();
        nft.burn(tokenId);

        uint256[] memory tokensAfter = nft.getUserOwnedTokens(alice);
        assertEq(tokensAfter.length, 1);

        // getCurrentController returns address(0) after burn
        assertEq(nft.getCurrentController(alice), alice);
    }

    // ============ MULTIPLE INHERITANCE CHAINS ============

    function test_ConcurrentInheritanceToSameBeneficiary() public {
        // Bob will receive transfers from multiple estates
        vm.prank(bob);
        nft.mint();

        // Alice's estate
        vm.prank(alice);
        nft.mint();
        vm.prank(alice);
        address registry1 = registryFactory.createRegistry();
        vm.prank(alice);
        SimpleSuccessionRegistry(registry1).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Charlie's estate
        vm.prank(charlie);
        nft.mint();
        vm.prank(charlie);
        address registry2 = registryFactory.createRegistry();
        vm.prank(charlie);
        SimpleSuccessionRegistry(registry2).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        // Bob receives both estates
        vm.prank(bob);
        SimpleSuccessionRegistry(registry1).executeSuccession();

        vm.prank(bob);
        SimpleSuccessionRegistry(registry2).executeSuccession();

        // Bob now has 3 tokens (his own + 2 inherited)
        assertEq(nft.getUserOwnedTokens(bob).length, 3);
    }

    // ============ CONFIGURATION EDGE CASES ============

    function test_CannotUseUnconfiguredRegistry() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        // Check-in should fail when not configured
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.NotConfigured.selector);
        SimpleSuccessionRegistry(registry).checkIn();

        // Update beneficiary should fail when not configured
        vm.prank(alice);
        vm.expectRevert(SimpleSuccessionRegistry.NotConfigured.selector);
        SimpleSuccessionRegistry(registry).updateBeneficiary(bob);
    }

    // ============ GAS USAGE TRACKING ============

    function test_OneTokenSuccessionGas() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        vm.warp(block.timestamp + 181 days);

        uint256 gasStart = gasleft();
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();
        uint256 gasUsed = gasStart - gasleft();

        emit log_named_uint("Internal Execution Gas, not Tx Gas used for single token transfer", gasUsed);

        // Verify bob received 1 token
        uint256 bobTokens = nft.getUserOwnedTokens(bob).length;
        console.log("Bob received tokens:", bobTokens);
        assertEq(bobTokens, 1);
    }

    /// @notice Measure gas specifically for 2-token succession
    function test_TwoTokenSuccessionGas() public {
        // Setup: 1 predecessor passes NFT to alice
        address predecessor = makeAddr("pred");
        vm.deal(predecessor, 1 ether);

        vm.startPrank(predecessor);
        nft.mint();
        address predRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(predRegistry)
            .setupSimplePolicy(alice, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        // Time passes, alice claims
        skip(180 days + 1);
        vm.prank(alice);
        SimpleSuccessionRegistry(predRegistry).executeSuccession();

        // Verify alice has 1 inherited token
        assertEq(nft.getUserOwnedTokens(alice).length, 1);
        console.log("Alice has 1 inherited token");

        // Alice mints her own NFT (now has 2 total: 1 inherited + 1 original)
        vm.startPrank(alice);
        nft.mint();
        address aliceRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(aliceRegistry)
            .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        // Verify alice has 2 tokens total
        uint256 aliceTokens = nft.getUserOwnedTokens(alice).length;
        console.log("Alice total tokens:", aliceTokens);
        assertEq(aliceTokens, 2);

        // Time passes, alice inactive
        skip(180 days + 1);

        // THIS IS THE MEASUREMENT - Bob executes succession on 2 tokens
        vm.prank(bob);
        SimpleSuccessionRegistry(aliceRegistry).executeSuccession();

        // Verify bob received 2 tokens
        uint256 bobTokens = nft.getUserOwnedTokens(bob).length;
        console.log("Bob received tokens:", bobTokens);
        assertEq(bobTokens, 2);
    }

    /// @notice Measure gas for transferring MAX_INHERITED_TOKENS (8) in single succession
    function test_SingleSuccession_MaxTokenTransfer() public {
        // Setup: 8 different people each pass their NFT to alice
        address[] memory predecessors = new address[](8);

        // Explicitly define wait period (6 months = ~180 days)
        uint256 waitPeriod = 180 days;

        for (uint256 i = 0; i < 8; i++) {
            predecessors[i] = makeAddr(string.concat("pred", vm.toString(i)));
            vm.deal(predecessors[i], 1 ether);

            // Each predecessor: mint, setup succession to alice
            vm.startPrank(predecessors[i]);
            nft.mint();
            address predRegistry = registryFactory.createRegistry();
            SimpleSuccessionRegistry(predRegistry)
                .setupSimplePolicy(alice, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
            vm.stopPrank();

            // ADVANCE time by wait period + 1 (relative, not absolute)
            skip(waitPeriod + 1);

            // Alice claims this predecessor's NFT
            vm.prank(alice);
            SimpleSuccessionRegistry(predRegistry).executeSuccession();

            console.log("Alice claimed from predecessor", i);
        }

        // Alice now has 8 inherited tokens
        uint256 aliceTokens = nft.getUserOwnedTokens(alice).length;
        console.log("Alice inherited tokens:", aliceTokens);
        assertEq(aliceTokens, 8);

        // Alice mints her own NFT (now has 9 total: 8 inherited + 1 original)
        vm.startPrank(alice);
        nft.mint();
        address aliceRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(aliceRegistry)
            .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        uint256 aliceTotalTokens = nft.getUserOwnedTokens(alice).length;
        console.log("Alice total tokens (inherited + original):", aliceTotalTokens);
        assertEq(aliceTotalTokens, 9);

        // ADVANCE time by wait period + 1 (relative, not absolute)
        skip(waitPeriod + 1);

        // THIS IS THE KEY MEASUREMENT - Bob executing succession on 9 tokens
        vm.prank(bob);
        SimpleSuccessionRegistry(aliceRegistry).executeSuccession();

        // Verify bob got 8 tokens (the limit)
        uint256 bobTokens = nft.getUserOwnedTokens(bob).length;
        console.log("Bob received tokens:", bobTokens);
        assertEq(bobTokens, 8, "Bob should receive MAX_INHERITED_TOKENS (8)");

        // Verify alice still has 1 token (her original, which wasn't transferred)
        uint256 aliceRemainingTokens = nft.getUserOwnedTokens(alice).length;
        console.log("Alice remaining tokens:", aliceRemainingTokens);
        assertEq(aliceRemainingTokens, 1, "Alice should retain 1 token (partial transfer)");
    }
}
