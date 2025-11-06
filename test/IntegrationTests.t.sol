// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

/**
 * @title IntegrationTests
 * @notice Tests complete workflows and multi-component interactions
 * @dev Only true integration tests - unit tests belong in component-specific files
 */
contract IntegrationTests is BaseTest {
    // ============ COMPLETE ESTATE FLOW ============

    function test_CompleteEstateLifecycle() public {
        // Setup: Alice creates complete estate
        vm.startPrank(alice);

        // 1. Mint NFT
        nft.mint();
        uint256 aliceTokenId = 1;

        // 2. Create registry
        address registry = registryFactory.createRegistry();

        // 3. Configure succession
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        // 4. Create multiple accounts
        address account1 = accountFactory.createAccount();
        address account2 = accountFactory.createAccount();

        vm.stopPrank();

        // 5. Fund accounts
        vm.deal(account1, 50 ether);
        vm.deal(account2, 25 ether);

        // Verify initial state
        assertEq(nft.getCurrentController(alice), alice);
        assertEq(SimpleAccount(payable(account1)).getCurrentNFTController(), alice);
        assertEq(SimpleAccount(payable(account2)).getCurrentNFTController(), alice);

        // Alice checks in periodically
        vm.warp(block.timestamp + 30 days);
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();

        vm.warp(block.timestamp + 60 days);
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).checkIn();

        // Alice becomes inactive
        vm.warp(block.timestamp + 366 days); // Total 366 days from last check-in

        // Bob executes succession
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Verify succession
        assertEq(nft.ownerOf(aliceTokenId), bob);
        assertEq(nft.getCurrentController(alice), bob);

        // Bob controls all accounts
        assertEq(SimpleAccount(payable(account1)).getCurrentNFTController(), bob);
        assertEq(SimpleAccount(payable(account2)).getCurrentNFTController(), bob);
        assertTrue(SimpleAccount(payable(account1)).hasSuccessionOccurred());

        // Bob can sweep assets
        vm.startPrank(bob);
        SimpleAccount(payable(account1)).sweepAllNative();
        SimpleAccount(payable(account2)).sweepAllNative();
        assertEq(bob.balance, 175 ether); // Initial 100 + swept 75
        vm.stopPrank();
    }

    // ============ CHAINED INHERITANCE ============

    function test_ThreeGenerationInheritance() public {
        // Generation 1: Alice
        vm.startPrank(alice);
        nft.mint();
        address aliceRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(aliceRegistry)
            .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        address aliceAccount = accountFactory.createAccount();
        vm.stopPrank();

        vm.deal(aliceAccount, 100 ether);

        // Generation 2: Bob
        vm.startPrank(bob);
        nft.mint();
        address bobRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(bobRegistry)
            .setupSimplePolicy(charlie, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        address bobAccount = accountFactory.createAccount();
        vm.stopPrank();

        vm.deal(bobAccount, 50 ether);

        // Generation 3: Charlie
        vm.startPrank(charlie);
        nft.mint();
        address charlieRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(charlieRegistry)
            .setupSimplePolicy(david, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        address charlieAccount = accountFactory.createAccount();
        vm.stopPrank();

        vm.deal(charlieAccount, 25 ether);

        // Execute Alice -> Bob succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(aliceRegistry).executeSuccession();

        // Bob now controls Alice's assets
        assertEq(nft.getCurrentController(alice), bob);
        assertEq(SimpleAccount(payable(aliceAccount)).getCurrentNFTController(), bob);

        // Execute Bob -> Charlie succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(charlie);
        SimpleSuccessionRegistry(bobRegistry).executeSuccession();

        // Charlie controls both Alice's and Bob's assets
        assertEq(nft.getCurrentController(alice), charlie);
        assertEq(nft.getCurrentController(bob), charlie);
        assertEq(SimpleAccount(payable(aliceAccount)).getCurrentNFTController(), charlie);
        assertEq(SimpleAccount(payable(bobAccount)).getCurrentNFTController(), charlie);

        // Charlie can manage all inherited assets
        vm.startPrank(charlie);
        SimpleAccount(payable(aliceAccount)).sweepAllNative();
        SimpleAccount(payable(bobAccount)).sweepAllNative();
        assertEq(charlie.balance, 250 ether); // Initial 100 + swept 150
        vm.stopPrank();
    }

    // ============ MULTI-ACCOUNT SUCCESSION ============

    function test_MultipleAccountsInheritance() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Create multiple accounts
        uint256 accountCount = 5;
        address[] memory accounts = new address[](accountCount);

        for (uint256 i = 0; i < accountCount; i++) {
            accounts[i] = accountFactory.createAccount();
            // Fund each account
            vm.deal(accounts[i], 10 ether);
        }

        vm.stopPrank();

        // Verify all controlled by Alice
        for (uint256 i = 0; i < accountCount; i++) {
            assertEq(SimpleAccount(payable(accounts[i])).getCurrentNFTController(), alice);
        }

        // Execute succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // All accounts now controlled by Bob
        for (uint256 i = 0; i < accountCount; i++) {
            assertEq(SimpleAccount(payable(accounts[i])).getCurrentNFTController(), bob);
        }

        // Bob can sweep all accounts
        vm.startPrank(bob);
        for (uint256 i = 0; i < accountCount; i++) {
            SimpleAccount(payable(accounts[i])).sweepAllNative();
        }
        assertEq(bob.balance, 150 ether); // Initial 100 + swept 50
        vm.stopPrank();
    }

    // ============ FACTORY AUTHORIZATION FLOW ============

    function test_FactoryAuthorizationMechanism() public {
        // Alice mints NFT
        vm.prank(alice);
        nft.mint();

        // Registry creation auto-authorizes
        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        // Verify registry is authorized
        assertTrue(nft.isAuthorizedRegistry(alice, registry));

        // Registry can transfer NFT through succession
        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        assertEq(nft.ownerOf(1), bob);
    }

    // ============ MIXED ASSET SUCCESSION ============

    function test_MixedAssetSuccession() public {
        // Deploy test tokens
        MockERC20 token = new MockERC20("Test", "TST", 18);
        MockERC721 nftToken = new MockERC721("NFT", "NFT");

        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        address account = accountFactory.createAccount();
        vm.stopPrank();

        // Fund account with various assets
        vm.deal(account, 25 ether);
        token.mint(account, 1000e18);
        nftToken.mint(account, 1);
        nftToken.mint(account, 2);
        nftToken.mint(account, 3);

        // Execute succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Bob controls all assets
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), bob);

        // Bob sweeps all assets
        vm.startPrank(bob);
        SimpleAccount(payable(account)).sweepAllNative();
        SimpleAccount(payable(account)).sweepAllERC20(address(token));
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), bob, 1);
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), bob, 2);
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), bob, 3);

        assertEq(bob.balance, 125 ether);
        assertEq(token.balanceOf(bob), 1000e18);
        assertEq(nftToken.ownerOf(1), bob);
        assertEq(nftToken.ownerOf(2), bob);
        assertEq(nftToken.ownerOf(3), bob);
        vm.stopPrank();
    }

    // ============ STATUS QUERIES THROUGH LIFECYCLE ============

    function test_StatusQueriesThroughLifecycle() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();

        // Before configuration
        (string memory mode, address beneficiary, uint256 daysUntil, bool claimable) =
            SimpleSuccessionRegistry(registry).getStatus();
        assertEq(mode, "Not Configured");
        assertEq(beneficiary, address(0));

        // After configuration
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.ONE_YEAR);

        (mode, beneficiary, daysUntil, claimable) = SimpleSuccessionRegistry(registry).getStatus();
        assertEq(mode, "Simple");
        assertEq(beneficiary, bob);
        assertEq(daysUntil, 365);
        assertFalse(claimable);

        // Halfway through
        vm.warp(block.timestamp + 180 days);
        (,, daysUntil, claimable) = SimpleSuccessionRegistry(registry).getStatus();
        assertEq(daysUntil, 185);
        assertFalse(claimable);

        // After check-in (resets timer)
        SimpleSuccessionRegistry(registry).checkIn();
        (,, daysUntil, claimable) = SimpleSuccessionRegistry(registry).getStatus();
        assertEq(daysUntil, 365);
        assertFalse(claimable);

        vm.stopPrank();

        // After waiting period
        vm.warp(block.timestamp + 366 days);
        (,, daysUntil, claimable) = SimpleSuccessionRegistry(registry).getStatus();
        assertEq(daysUntil, 0);
        assertTrue(claimable);
    }

    // ============ CROSS-FACTORY INTEGRATION ============

    function test_CrossFactoryIntegration() public {
        // Single transaction flow
        vm.startPrank(alice);

        nft.mint();
        address registry = registryFactory.createRegistry();
        address account1 = accountFactory.createAccount();
        address account2 = accountFactory.createAccount();

        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.stopPrank();

        // Verify all components linked correctly
        assertTrue(nft.isAuthorizedRegistry(alice, registry));
        assertEq(registryFactory.userRegistry(alice), registry);
        assertEq(accountFactory.getUserAccountCount(alice), 2);

        address[] memory accounts = accountFactory.getUserAccounts(alice);
        assertEq(accounts[0], account1);
        assertEq(accounts[1], account2);

        // Verify control chain
        assertEq(SimpleAccount(payable(account1)).getControllerNFT(), address(nft));
        assertEq(SimpleAccount(payable(account1)).getOriginalHolder(), alice);
        assertEq(SimpleAccount(payable(account1)).getCurrentNFTController(), alice);
    }

    // ============ INHERITANCE LIMIT INTEGRATION ============

    function test_InheritanceLimitAcrossMultipleEstates() public {
        uint256 maxTokens = nft.MAX_INHERITED_TOKENS();

        // Create users who will all leave estates to Bob
        address[] memory users = new address[](maxTokens + 2);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = makeAddr(string.concat("user", vm.toString(i)));
            vm.deal(users[i], 10 ether);

            vm.startPrank(users[i]);
            nft.mint();
            address reg = registryFactory.createRegistry();
            SimpleSuccessionRegistry(reg).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
            vm.stopPrank();
        }

        // Bob mints his own
        vm.prank(bob);
        nft.mint();

        // Execute multiple successions
        vm.warp(block.timestamp + 181 days);

        // First maxTokens-1 should work (Bob has 1, can receive maxTokens-1 more)
        for (uint256 i = 0; i < maxTokens - 1; i++) {
            address userRegistry = registryFactory.userRegistry(users[i]);

            vm.prank(bob);
            SimpleSuccessionRegistry(userRegistry).executeSuccession();
        }

        // Bob now has max tokens
        assertEq(nft.getUserOwnedTokens(bob).length, maxTokens);

        // Next transfers should fail
        for (uint256 i = maxTokens - 1; i < users.length; i++) {
            address userRegistry = registryFactory.userRegistry(users[i]);

            vm.prank(bob);
            vm.expectRevert();
            SimpleSuccessionRegistry(userRegistry).executeSuccession();
        }
    }

    // ============ SPAM CLEARING WORKFLOW ============

    function test_SpamTokenManagementWorkflow() public {
        // Give Bob multiple unwanted tokens
        for (uint256 i = 0; i < 3; i++) {
            address spammer = makeAddr(string.concat("spammer", vm.toString(i)));
            vm.deal(spammer, 10 ether);

            vm.startPrank(spammer);
            nft.mint();
            address spamRegistry = registryFactory.createRegistry();
            SimpleSuccessionRegistry(spamRegistry)
                .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
            vm.stopPrank();
        }

        // Bob mints his own
        vm.prank(bob);
        nft.mint();

        // Execute spam transfers
        vm.warp(block.timestamp + 180 days);
        for (uint256 i = 0; i < 3; i++) {
            address spammer = makeAddr(string.concat("spammer", vm.toString(i)));
            address userRegistry = registryFactory.userRegistry(spammer);

            vm.prank(bob);
            SimpleSuccessionRegistry(userRegistry).executeSuccession();
        }

        // Bob now has 4 tokens (his own + 3 spam)
        assertEq(nft.getUserOwnedTokens(bob).length, 4);

        // Alice sets up estate for Bob
        vm.startPrank(alice);
        nft.mint();
        address aliceRegistry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(aliceRegistry)
            .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        vm.stopPrank();

        // Bob burns spam tokens directly through NFT contract
        for (uint256 i = 0; i < 3; i++) {
            address spammer = makeAddr(string.concat("spammer", vm.toString(i)));
            uint256 spamTokenId = nft.originalTokenId(spammer);
            vm.prank(bob);
            nft.burn(spamTokenId);
        }

        // Verify Bob cleared the spam tokens
        assertEq(nft.getUserOwnedTokens(bob).length, 1);

        // Now Bob can claim Alice's estate
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(aliceRegistry).executeSuccession();

        // Bob has 2 tokens (his own + Alice's)
        assertEq(nft.getUserOwnedTokens(bob).length, 2);
    }

    // ============ ACCOUNT INFO INTEGRATION ============

    function test_AccountInfoThroughSuccession() public {
        vm.startPrank(alice);
        nft.mint();
        address registry = registryFactory.createRegistry();
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        address account = accountFactory.createAccount();
        vm.stopPrank();

        vm.deal(account, 50 ether);

        // Before succession
        (address originalOwner, address currentController, bool hasSucceeded, uint256 nativeBalance, uint256 chainId) =
            SimpleAccount(payable(account)).getAccountInfo();

        assertEq(originalOwner, alice);
        assertEq(currentController, alice);
        assertFalse(hasSucceeded);
        assertEq(nativeBalance, 50 ether);
        assertEq(chainId, block.chainid);

        // Execute succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // After succession
        (originalOwner, currentController, hasSucceeded, nativeBalance, chainId) =
            SimpleAccount(payable(account)).getAccountInfo();

        assertEq(originalOwner, alice); // holder never changes
        assertEq(currentController, bob); // Controller changed
        assertTrue(hasSucceeded); // Succession occurred
        assertEq(nativeBalance, 50 ether);
        assertEq(chainId, block.chainid);
    }
}

// ============ MOCK CONTRACTS FOR TESTING ============

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    string public name;
    string public symbol;
    uint8 public decimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockERC721 {
    mapping(uint256 => address) public ownerOf;
    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function safeTransferFrom(address, address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }
}
