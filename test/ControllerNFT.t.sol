// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";
import "../contracts/interfaces/IControllerNFT.sol";
import "../contracts/interfaces/ISuccessionRegistry.sol";

contract ControllerNFTTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Minting ============

    function test_MintFirstNFT() public {
        vm.startPrank(alice);

        vm.expectEmit(true, true, false, true);
        emit IControllerNFT.ControllerNFTMinted(alice, 1);

        nft.mint();

        assertEq(nft.ownerOf(1), alice);
        assertTrue(nft.hasMinted(alice));
        assertEq(nft.originalTokenId(alice), 1);
        assertEq(nft.totalMinted(), 1);

        vm.stopPrank();
    }

    function test_RevertWhen_MintingTwice() public {
        vm.startPrank(alice);
        nft.mint();

        vm.expectRevert(IControllerNFT.AlreadyMinted.selector);
        nft.mint();

        vm.stopPrank();
    }

    function test_MintMultipleUsers() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(bob);
        nft.mint();

        vm.prank(charlie);
        nft.mint();

        assertEq(nft.totalMinted(), 3);
        assertEq(nft.nextTokenId(), 4);

        assertTrue(nft.hasMinted(alice));
        assertTrue(nft.hasMinted(bob));
        assertTrue(nft.hasMinted(charlie));
    }

    // ============ Transfer Restrictions ============

    function test_RevertWhen_TransferringNormally() public {
        vm.startPrank(alice);
        nft.mint();
        uint256 tokenId = nft.originalTokenId(alice);

        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.transferFrom(alice, bob, tokenId);

        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.safeTransferFrom(alice, bob, tokenId);

        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.safeTransferFrom(alice, bob, tokenId, "");

        vm.stopPrank();
    }

    function test_RevertWhen_ApprovingNFT() public {
        vm.startPrank(alice);
        nft.mint();
        uint256 tokenId = nft.originalTokenId(alice);

        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.approve(bob, tokenId);

        vm.expectRevert(IControllerNFT.RegistryLinkedToken.selector);
        nft.setApprovalForAll(bob, true);

        vm.stopPrank();
    }

    // ============ Registry Authorization ============

    function test_AutoAuthorizeRegistryViaFactory() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        assertTrue(nft.isAuthorizedRegistry(alice, registry));
    }

    function test_RevertWhen_UnauthorizedFactoryAuthorizes() public {
        address fakeFactory = makeAddr("fakeFactory");
        address fakeRegistry = makeAddr("fakeRegistry");

        vm.prank(alice);
        nft.mint();

        vm.prank(fakeFactory);
        vm.expectRevert(ControllerNFT.NotTrustedFactory.selector);
        nft.authorizeRegistry(alice, fakeRegistry);
    }

    function test_RevertWhen_FactoryAuthorizesWrongRegistry() public {
        vm.prank(alice);
        nft.mint();

        address wrongRegistry = makeAddr("wrongRegistry");

        vm.prank(address(registryFactory));
        vm.expectRevert(ControllerNFT.NotAuthorized.selector);
        nft.authorizeRegistry(alice, wrongRegistry);
    }

    // ============ getCurrentController ============

    function test_GetCurrentController_NormalCase() public {
        vm.prank(alice);
        nft.mint();

        assertEq(nft.getCurrentController(alice), alice);
    }

    function test_GetCurrentController_AfterSuccession() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        assertEq(nft.getCurrentController(alice), bob);
    }

    function test_GetCurrentController_NeverMinted() public view {
        assertEq(nft.getCurrentController(alice), address(0));
    }

    function test_GetCurrentController_AfterBurn() public {
        vm.startPrank(alice);
        nft.mint();
        uint256 tokenId = nft.originalTokenId(alice);

        vm.expectRevert();
        nft.burn(tokenId);
        vm.stopPrank();

        assertEq(nft.getCurrentController(alice), alice);
    }

    // ============ Burning ============

    function test_BurnOwnToken() public {
        vm.startPrank(alice);
        nft.mint();
        uint256 tokenId = nft.originalTokenId(alice);

        vm.expectRevert();
        nft.burn(tokenId);

        assertEq(nft.ownerOf(tokenId), alice);

        vm.stopPrank();
    }

    function test_RevertWhen_BurningOthersToken() public {
        vm.prank(alice);
        nft.mint();
        uint256 tokenId = nft.originalTokenId(alice);

        vm.prank(bob);
        vm.expectRevert(ControllerNFT.NotAuthorized.selector);
        nft.burn(tokenId);
    }

    function test_BurnInheritedToken() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        uint256 aliceTokenId = nft.originalTokenId(alice);

        vm.prank(bob);
        nft.burn(aliceTokenId);

        vm.expectRevert();
        nft.ownerOf(aliceTokenId);
    }

    // ============ Inheritance Limits ============

    function test_InheritanceLimit_MaxTokens() public {
        uint256 maxTokens = nft.MAX_INHERITED_TOKENS();

        vm.prank(bob);
        nft.mint();

        address[] memory users = new address[](maxTokens);
        address[] memory registries = new address[](maxTokens);

        for (uint256 i = 0; i < maxTokens; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            vm.deal(users[i], 10 ether);

            vm.prank(users[i]);
            nft.mint();

            vm.prank(users[i]);
            registries[i] = registryFactory.createRegistry();

            vm.prank(users[i]);
            SimpleSuccessionRegistry(registries[i])
                .setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);
        }

        vm.warp(block.timestamp + 181 days);

        // Bob can receive maxTokens - 1 more (he already has 1)
        for (uint256 i = 0; i < maxTokens - 1; i++) {
            vm.prank(bob);
            SimpleSuccessionRegistry(registries[i]).executeSuccession();
        }

        // Verify bob received 7 token + his own = 8
        uint256 bobTokens = nft.getUserOwnedTokens(bob).length;
        console.log("Bob received tokens:", bobTokens);
        assertEq(bobTokens, 8);

        // Next one should fail
        vm.prank(bob);
        vm.expectRevert();
        SimpleSuccessionRegistry(registries[maxTokens - 1]).executeSuccession();
    }

    // ============ Factory Trust ============

    function test_SetTrustedFactory() public {
        address newFactory = makeAddr("newFactory");

        vm.prank(deployer);
        nft.setTrustedFactory(newFactory, true);

        assertTrue(nft.isTrustedFactory(newFactory));

        vm.prank(deployer);
        nft.setTrustedFactory(newFactory, false);

        assertFalse(nft.isTrustedFactory(newFactory));
    }

    function test_RevertWhen_NonOwnerSetsTrustedFactory() public {
        address newFactory = makeAddr("newFactory");

        vm.prank(alice);
        vm.expectRevert();
        nft.setTrustedFactory(newFactory, true);
    }

    // ============ View Functions ============

    function test_GetUserOwnedTokens_Single() public {
        vm.prank(alice);
        nft.mint();

        uint256[] memory tokens = nft.getUserOwnedTokens(alice);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], 1);
    }

    function test_GetUserOwnedTokens_Multiple() public {
        vm.prank(alice);
        nft.mint();

        vm.prank(bob);
        nft.mint();

        vm.prank(bob);
        address bobRegistry = registryFactory.createRegistry();

        vm.prank(bob);
        SimpleSuccessionRegistry(bobRegistry)
            .setupSimplePolicy(alice, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);

        vm.prank(alice);
        SimpleSuccessionRegistry(bobRegistry).executeSuccession();

        uint256[] memory tokens = nft.getUserOwnedTokens(alice);
        assertEq(tokens.length, 2);
    }

    function test_GetUserOwnedTokens_AfterBurn() public {
        vm.prank(alice);
        nft.mint();

        uint256 tokenId = nft.originalTokenId(alice);

        vm.prank(alice);
        vm.expectRevert();
        nft.burn(tokenId);

        uint256[] memory tokens = nft.getUserOwnedTokens(alice);
        assertEq(tokens.length, 1);
    }

    // ============ Counter Functions ============

    function test_NextTokenId_Increments() public {
        assertEq(nft.nextTokenId(), 1);

        vm.prank(alice);
        nft.mint();
        assertEq(nft.nextTokenId(), 2);

        vm.prank(bob);
        nft.mint();
        assertEq(nft.nextTokenId(), 3);
    }

    function test_TotalMinted_Increments() public {
        assertEq(nft.totalMinted(), 0);

        vm.prank(alice);
        nft.mint();
        assertEq(nft.totalMinted(), 1);

        vm.prank(bob);
        nft.mint();
        assertEq(nft.totalMinted(), 2);
    }

    function test_OriginalTokenId_ZeroWhenNotMinted() public view {
        assertEq(nft.originalTokenId(alice), 0);
        assertFalse(nft.hasMinted(alice));
    }
}
