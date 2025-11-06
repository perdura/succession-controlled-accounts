// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";
import "../contracts/reference/NFTLinked.sol";
import "../contracts/interfaces/IControllerNFT.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract NFTLinkedMock is NFTLinked {
    bool public initialized;

    function initialize(address _controllerNFT, address _originalHolder) external {
        require(!initialized, "Already initialized");
        initialized = true;
        _initializeNFTLinking(_controllerNFT, _originalHolder);
    }

    function restrictedFunction() external view onlyController returns (bool) {
        return true;
    }

    function exposeCurrentController() public view returns (address) {
        return getCurrentNFTController();
    }
}

contract MockControllerNFT {
    mapping(address => address) private controllers;
    mapping(address => bool) private hasMintedMap;
    mapping(address => uint256) private tokenIds;

    function setController(address originalHolder, address controller) external {
        controllers[originalHolder] = controller;
        hasMintedMap[originalHolder] = true;
        if (tokenIds[originalHolder] == 0) {
            tokenIds[originalHolder] = 1;
        }
    }

    function getCurrentController(address originalHolder) external view returns (address) {
        return controllers[originalHolder];
    }

    function hasMinted(address user) external view returns (bool) {
        return hasMintedMap[user];
    }

    function originalTokenId(address user) external view returns (uint256) {
        return tokenIds[user];
    }

    function burnToken(address originalHolder) external {
        controllers[originalHolder] = address(0);
    }
}

contract NFTLinkedTest is BaseTest {
    NFTLinkedMock public nftLinked;
    MockControllerNFT public mockNFT;

    address constant ORIGINAL_HOLDER = address(0x1234);
    address constant NEW_CONTROLLER = address(0x5678);
    address constant UNAUTHORIZED = address(0x9999);

    function setUp() public override {
        super.setUp();

        mockNFT = new MockControllerNFT();
        nftLinked = new NFTLinkedMock();
    }

    // ============ Initialization ============

    function test_InitializeNFTLinking_Success() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        assertEq(nftLinked.getControllerNFT(), address(mockNFT));
        assertEq(nftLinked.getOriginalHolder(), ORIGINAL_HOLDER);
        assertTrue(nftLinked.initialized());
    }

    function test_InitializeEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit INFTLinked.NFTLinkingInitialized(address(mockNFT), ORIGINAL_HOLDER);

        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
    }

    function test_RevertWhen_InitializeWithZeroControllerNFT() public {
        vm.expectRevert(NFTLinked.ZeroControllerNFT.selector);
        nftLinked.initialize(address(0), ORIGINAL_HOLDER);
    }

    function test_RevertWhen_InitializeWithZeroOriginalHolder() public {
        vm.expectRevert(NFTLinked.ZeroOriginalHolder.selector);
        nftLinked.initialize(address(mockNFT), address(0));
    }

    function test_RevertWhen_InitializeTwice() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        vm.expectRevert("Already initialized");
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
    }

    // ============ hasSuccessionOccurred ============

    function test_HasSuccessionOccurred_NoController() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        assertFalse(nftLinked.hasSuccessionOccurred());
    }

    function test_HasSuccessionOccurred_SameController() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);

        assertFalse(nftLinked.hasSuccessionOccurred());
    }

    function test_HasSuccessionOccurred_DifferentController() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, NEW_CONTROLLER);

        assertTrue(nftLinked.hasSuccessionOccurred());
    }

    function test_HasSuccessionOccurred_AfterBurn() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);
        assertFalse(nftLinked.hasSuccessionOccurred());

        mockNFT.setController(ORIGINAL_HOLDER, NEW_CONTROLLER);
        assertTrue(nftLinked.hasSuccessionOccurred());

        mockNFT.burnToken(ORIGINAL_HOLDER);
        assertFalse(nftLinked.hasSuccessionOccurred());
    }

    // ============ onlyController Modifier ============

    function test_OnlyController_Success() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);

        vm.prank(ORIGINAL_HOLDER);
        assertTrue(nftLinked.restrictedFunction());
    }

    function test_OnlyController_Revert() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        nftLinked.restrictedFunction();
    }

    function test_OnlyController_AfterSuccession() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, NEW_CONTROLLER);

        vm.prank(NEW_CONTROLLER);
        assertTrue(nftLinked.restrictedFunction());

        vm.prank(ORIGINAL_HOLDER);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        nftLinked.restrictedFunction();
    }

    function test_OnlyController_NoController() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        vm.prank(address(0));
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        nftLinked.restrictedFunction();

        vm.prank(ORIGINAL_HOLDER);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        nftLinked.restrictedFunction();
    }

    // ============ getCurrentNFTController ============

    function test_GetCurrentNFTController_Variations() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        assertEq(nftLinked.getCurrentNFTController(), address(0));

        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);
        assertEq(nftLinked.getCurrentNFTController(), ORIGINAL_HOLDER);

        mockNFT.setController(ORIGINAL_HOLDER, NEW_CONTROLLER);
        assertEq(nftLinked.getCurrentNFTController(), NEW_CONTROLLER);

        mockNFT.burnToken(ORIGINAL_HOLDER);
        assertEq(nftLinked.getCurrentNFTController(), address(0));
    }

    // ============ View Functions ============

    function test_GetControllerNFT() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        assertEq(nftLinked.getControllerNFT(), address(mockNFT));
    }

    function test_GetOriginalHolder() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        assertEq(nftLinked.getOriginalHolder(), ORIGINAL_HOLDER);
    }

    // ============ Complete Lifecycle ============

    function test_CompleteLifecycle() public {
        NFTLinkedMock linked = new NFTLinkedMock();

        linked.initialize(address(mockNFT), alice);
        assertEq(linked.getOriginalHolder(), alice);
        assertEq(linked.getControllerNFT(), address(mockNFT));

        assertEq(linked.getCurrentNFTController(), address(0));
        assertFalse(linked.hasSuccessionOccurred());

        mockNFT.setController(alice, alice);
        assertEq(linked.getCurrentNFTController(), alice);
        assertFalse(linked.hasSuccessionOccurred());

        vm.prank(alice);
        assertTrue(linked.restrictedFunction());

        mockNFT.setController(alice, bob);
        assertEq(linked.getCurrentNFTController(), bob);
        assertTrue(linked.hasSuccessionOccurred());

        vm.prank(bob);
        assertTrue(linked.restrictedFunction());

        vm.prank(alice);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        linked.restrictedFunction();

        mockNFT.setController(alice, charlie);
        assertEq(linked.getCurrentNFTController(), charlie);
        assertTrue(linked.hasSuccessionOccurred());

        mockNFT.burnToken(alice);
        assertEq(linked.getCurrentNFTController(), address(0));
        assertFalse(linked.hasSuccessionOccurred());

        vm.prank(charlie);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        linked.restrictedFunction();
    }

    function test_MultipleLinkedContracts() public {
        NFTLinkedMock linked1 = new NFTLinkedMock();
        NFTLinkedMock linked2 = new NFTLinkedMock();
        NFTLinkedMock linked3 = new NFTLinkedMock();

        linked1.initialize(address(mockNFT), alice);
        linked2.initialize(address(mockNFT), alice);
        linked3.initialize(address(mockNFT), alice);

        mockNFT.setController(alice, alice);

        assertEq(linked1.getCurrentNFTController(), alice);
        assertEq(linked2.getCurrentNFTController(), alice);
        assertEq(linked3.getCurrentNFTController(), alice);

        assertFalse(linked1.hasSuccessionOccurred());
        assertFalse(linked2.hasSuccessionOccurred());
        assertFalse(linked3.hasSuccessionOccurred());

        mockNFT.setController(alice, bob);

        assertEq(linked1.getCurrentNFTController(), bob);
        assertEq(linked2.getCurrentNFTController(), bob);
        assertEq(linked3.getCurrentNFTController(), bob);

        assertTrue(linked1.hasSuccessionOccurred());
        assertTrue(linked2.hasSuccessionOccurred());
        assertTrue(linked3.hasSuccessionOccurred());

        vm.startPrank(bob);
        assertTrue(linked1.restrictedFunction());
        assertTrue(linked2.restrictedFunction());
        assertTrue(linked3.restrictedFunction());
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        linked1.restrictedFunction();

        vm.expectRevert(INFTLinked.NotNFTController.selector);
        linked2.restrictedFunction();

        vm.expectRevert(INFTLinked.NotNFTController.selector);
        linked3.restrictedFunction();
        vm.stopPrank();
    }

    // ============ Fuzz Tests ============

    function testFuzz_InitializeWithRandomAddresses(address nft, address holder) public {
        vm.assume(nft != address(0));
        vm.assume(holder != address(0));

        NFTLinkedMock newLinked = new NFTLinkedMock();
        newLinked.initialize(nft, holder);

        assertEq(newLinked.getControllerNFT(), nft);
        assertEq(newLinked.getOriginalHolder(), holder);
    }

    function testFuzz_OnlyControllerWithRandomCaller(address caller) public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, ORIGINAL_HOLDER);

        if (caller == ORIGINAL_HOLDER) {
            vm.prank(caller);
            assertTrue(nftLinked.restrictedFunction());
        } else {
            vm.prank(caller);
            vm.expectRevert(INFTLinked.NotNFTController.selector);
            nftLinked.restrictedFunction();
        }
    }

    function testFuzz_HasSuccessionWithRandomController(address controller) public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);

        if (controller == address(0)) {
            assertFalse(nftLinked.hasSuccessionOccurred());
        } else if (controller == ORIGINAL_HOLDER) {
            mockNFT.setController(ORIGINAL_HOLDER, controller);
            assertFalse(nftLinked.hasSuccessionOccurred());
        } else {
            mockNFT.setController(ORIGINAL_HOLDER, controller);
            assertTrue(nftLinked.hasSuccessionOccurred());
        }
    }

    // ============ Edge Cases ============

    function test_EdgeCase_ZeroAddressCannotCallRestricted() public {
        nftLinked.initialize(address(mockNFT), ORIGINAL_HOLDER);
        mockNFT.setController(ORIGINAL_HOLDER, address(0));

        vm.prank(address(0));
        vm.expectRevert(INFTLinked.NotNFTController.selector);
        nftLinked.restrictedFunction();
    }

    function test_EdgeCase_RapidControllerChanges() public {
        nftLinked.initialize(address(mockNFT), alice);

        address[5] memory controllers = [alice, bob, charlie, address(0x1111), address(0x2222)];

        for (uint256 i = 0; i < controllers.length; i++) {
            mockNFT.setController(alice, controllers[i]);
            assertEq(nftLinked.getCurrentNFTController(), controllers[i]);

            if (controllers[i] == alice) {
                assertFalse(nftLinked.hasSuccessionOccurred());
            } else {
                assertTrue(nftLinked.hasSuccessionOccurred());
            }

            vm.prank(controllers[i]);
            assertTrue(nftLinked.restrictedFunction());

            if (i > 0) {
                vm.prank(controllers[i - 1]);
                vm.expectRevert(INFTLinked.NotNFTController.selector);
                nftLinked.restrictedFunction();
            }
        }
    }
}
