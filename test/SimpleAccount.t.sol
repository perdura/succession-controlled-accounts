// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract SimpleAccountTest is BaseTest {
    address public account;
    MockERC20 public token;
    MockERC721 public nftToken;
    MockERC1155 public erc1155Token;

    function setUp() public override {
        super.setUp();

        // Alice creates account
        vm.startPrank(alice);
        nft.mint();
        account = accountFactory.createAccount();
        vm.stopPrank();

        // Deploy test tokens
        token = new MockERC20("Test", "TST", 18);
        nftToken = new MockERC721("TestNFT", "TNFT");
        erc1155Token = new MockERC1155("TestMulti", "TMULTI");
    }

    // ============ Initialization Tests ============

    function test_AccountInitialization() public view {
        SimpleAccount acc = SimpleAccount(payable(account));
        assertEq(acc.getOriginalHolder(), alice);
        assertEq(acc.getCurrentNFTController(), alice);
        assertEq(acc.getControllerNFT(), address(nft));
        assertFalse(acc.hasSuccessionOccurred());
    }

    function test_RevertWhen_InitializingTwice() public {
        SimpleAccount acc = SimpleAccount(payable(account));

        vm.prank(address(accountFactory));
        vm.expectRevert();
        acc.initialize(bob, address(nft), address(accountFactory));
    }

    function test_RevertWhen_NotFactoryInitializes() public {
        SimpleAccount newAcc = new SimpleAccount();

        vm.prank(alice);
        vm.expectRevert();
        newAcc.initialize(alice, address(nft), address(accountFactory));
    }

    function test_RevertWhen_ZeroAddressInitialization() public {
        SimpleAccount newAcc = new SimpleAccount();

        vm.prank(address(accountFactory));
        vm.expectRevert();
        newAcc.initialize(address(0), address(nft), address(accountFactory));

        vm.prank(address(accountFactory));
        vm.expectRevert();
        newAcc.initialize(alice, address(0), address(accountFactory));
    }

    function test_RevertWhen_InitializeCalledOnImplementation() public {
        vm.expectRevert();
        accountImpl.initialize(alice, address(nft), address(accountFactory));
    }

    // ============ Native Currency Tests ============

    function test_ReceiveNative() public {
        uint256 amount = 10 ether;

        vm.deal(bob, amount);
        vm.prank(bob);
        (bool success,) = account.call{value: amount}("");

        assertTrue(success);
        assertEq(account.balance, amount);
    }

    function test_SweepNative() public {
        // Fund account
        vm.deal(account, 10 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, 5 ether);

        assertEq(alice.balance - aliceBalanceBefore, 5 ether);
        assertEq(account.balance, 5 ether);
    }

    function test_SweepAllNative() public {
        vm.deal(account, 10 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepAllNative();

        assertEq(alice.balance - aliceBalanceBefore, 10 ether);
        assertEq(account.balance, 0);
    }

    function test_SweepNativeMax() public {
        vm.deal(account, 10 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, type(uint256).max);

        assertEq(alice.balance - aliceBalanceBefore, 10 ether);
        assertEq(account.balance, 0);
    }

    function test_RevertWhen_NotControllerSweepsNative() public {
        vm.deal(account, 10 ether);

        vm.prank(bob);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepNative(bob, 5 ether);
    }

    function test_RevertWhen_SendToZeroAddress() public {
        vm.deal(account, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepNative(address(0), 5 ether);
    }

    // ============ ERC20 Tests ============

    function test_SweepERC20() public {
        token.mint(account, 100e18);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC20(address(token), alice, 50e18);

        assertEq(token.balanceOf(alice), 50e18);
        assertEq(token.balanceOf(account), 50e18);
    }

    function test_SweepAllERC20() public {
        token.mint(account, 100e18);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepAllERC20(address(token));

        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(account), 0);
    }

    function test_SweepERC20Max() public {
        token.mint(account, 100e18);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC20(address(token), alice, type(uint256).max);

        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(account), 0);
    }

    function test_RevertWhen_NotControllerSweepsERC20() public {
        token.mint(account, 100e18);

        vm.prank(bob);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepERC20(address(token), bob, 50e18);
    }

    // ============ ERC721 Tests ============

    function test_SweepERC721() public {
        nftToken.mint(account, 1);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), alice, 1);

        assertEq(nftToken.ownerOf(1), alice);
    }

    function test_RevertWhen_NotControllerSweepsERC721() public {
        nftToken.mint(account, 1);

        vm.prank(bob);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), bob, 1);
    }

    // ============ Succession Tests ============

    function test_ControllerChangeAfterSuccession() public {
        // Setup succession
        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Initially Alice controls
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), alice);

        // Execute succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Now Bob controls
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), bob);
        assertTrue(SimpleAccount(payable(account)).hasSuccessionOccurred());

        // Bob can sweep assets
        vm.deal(account, 10 ether);
        vm.prank(bob);
        SimpleAccount(payable(account)).sweepAllNative();
        assertEq(bob.balance, 110 ether); // Initial 100 + swept 10
    }

    // ============ View Functions Tests ============

    function test_GetAccountInfo() public {
        vm.deal(account, 5 ether);

        (address originalOwner, address currentController, bool hasSucceeded, uint256 nativeBalance, uint256 chainId) =
            SimpleAccount(payable(account)).getAccountInfo();

        assertEq(originalOwner, alice);
        assertEq(currentController, alice);
        assertFalse(hasSucceeded);
        assertEq(nativeBalance, 5 ether);
        assertEq(chainId, block.chainid);
    }

    function test_GetBalances() public {
        vm.deal(account, 5 ether);
        token.mint(account, 100e18);

        assertEq(SimpleAccount(payable(account)).getNativeBalance(), 5 ether);
        assertEq(SimpleAccount(payable(account)).getTokenBalance(address(token)), 100e18);
    }

    // ============ ERC165 Support ============

    function test_SupportsInterface() public view {
        SimpleAccount acc = SimpleAccount(payable(account));

        // ERC721Receiver
        assertTrue(acc.supportsInterface(0x150b7a02));

        // ERC1155Receiver
        assertTrue(acc.supportsInterface(0x4e2312e0));

        // ERC165
        assertTrue(acc.supportsInterface(0x01ffc9a7));
    }

    // ============ NEW TESTS FOR ADDITIONAL COVERAGE ============

    // Additional Native Tests for Coverage
    function test_ReceiveNativeEmitsEvent() public {
        uint256 amount = 10 ether;

        vm.deal(bob, amount);
        vm.expectEmit(true, false, false, true, account);
        emit IControlledAccount.NativeReceived(bob, amount);

        vm.prank(bob);
        (bool success,) = account.call{value: amount}("");
        assertTrue(success);
    }

    function test_SweepNativeZeroAmount() public {
        vm.deal(account, 10 ether);

        // Sweeping 0 should work but do nothing
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, 0);

        assertEq(account.balance, 10 ether);
    }

    function test_SweepNativeMoreThanBalance() public {
        vm.deal(account, 10 ether);

        // Trying to sweep more than balance should revert
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.NativeSendFailed.selector);
        SimpleAccount(payable(account)).sweepNative(alice, 20 ether);
        assertEq(account.balance, 10 ether); // Should still have 10 since we asked for 20

        // Trying to sweep type(uint256).max should sweep full balance
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, type(uint256).max);
        assertEq(account.balance, 0 ether); // Should have 0
    }

    function test_SweepAllNativeWhenEmpty() public {
        // Should not revert even when balance is 0
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepAllNative();

        assertEq(account.balance, 0);
    }

    function test_SweepNativeEmitsEvent() public {
        vm.deal(account, 10 ether);

        vm.expectEmit(true, false, false, true, account);
        emit IControlledAccount.SweptNative(alice, 5 ether);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, 5 ether);
    }

    function test_RevertWhen_NativeSendFails() public {
        // Deploy a contract that rejects ETH
        RevertingReceiver reverter = new RevertingReceiver();
        vm.deal(account, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SimpleAccount.NativeSendFailed.selector);
        SimpleAccount(payable(account)).sweepNative(address(reverter), 5 ether);
    }

    // Additional ERC20 Tests for Coverage
    function test_SweepERC20ZeroAmount() public {
        token.mint(account, 100e18);

        // Should work but transfer nothing
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC20(address(token), alice, 0);

        assertEq(token.balanceOf(account), 100e18);
    }

    function test_SweepAllERC20WhenEmpty() public {
        // Should not revert even when balance is 0
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepAllERC20(address(token));

        assertEq(token.balanceOf(account), 0);
    }

    function test_SweepERC20EmitsEvent() public {
        token.mint(account, 100e18);

        vm.expectEmit(true, true, false, true, account);
        emit IControlledAccount.SweptERC20(address(token), alice, 50e18);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC20(address(token), alice, 50e18);
    }

    function test_RevertWhen_SweepERC20ZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC20(address(0), alice, 100e18);
    }

    function test_RevertWhen_SweepERC20ZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC20(address(token), address(0), 100e18);
    }

    function test_RevertWhen_SweepAllERC20ZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepAllERC20(address(0));
    }

    // Additional ERC721 Tests for Coverage
    function test_SweepERC721EmitsEvent() public {
        nftToken.mint(account, 1);

        vm.expectEmit(true, true, false, true, account);
        emit IControlledAccount.SweptERC721(address(nftToken), alice, 1);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), alice, 1);
    }

    function test_RevertWhen_SweepERC721ZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC721(address(0), alice, 1);
    }

    function test_RevertWhen_SweepERC721ZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC721(address(nftToken), address(0), 1);
    }

    function test_OnERC721Received() public view {
        bytes4 selector = SimpleAccount(payable(account)).onERC721Received(address(this), address(this), 1, "");
        assertEq(selector, IERC721Receiver.onERC721Received.selector);
    }

    // ERC1155 Tests for Coverage
    function test_SweepERC1155() public {
        erc1155Token.mint(account, 1, 100, "");

        vm.expectEmit(true, true, false, true, account);
        emit IControlledAccount.SweptERC1155(address(erc1155Token), alice, 1, 50);

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC1155(address(erc1155Token), alice, 1, 50, "");

        assertEq(erc1155Token.balanceOf(alice, 1), 50);
        assertEq(erc1155Token.balanceOf(account, 1), 50);
    }

    function test_SweepERC1155ZeroAmount() public {
        erc1155Token.mint(account, 1, 100, "");

        // Should work but transfer nothing
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC1155(address(erc1155Token), alice, 1, 0, "");

        assertEq(erc1155Token.balanceOf(account, 1), 100);
    }

    function test_RevertWhen_SweepERC1155ZeroToken() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC1155(address(0), alice, 1, 100, "");
    }

    function test_RevertWhen_SweepERC1155ZeroRecipient() public {
        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC1155(address(erc1155Token), address(0), 1, 100, "");
    }

    function test_RevertWhen_NotControllerSweepsERC1155() public {
        erc1155Token.mint(account, 1, 100, "");

        vm.prank(bob);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepERC1155(address(erc1155Token), bob, 1, 50, "");
    }

    function test_SweepERC1155Batch() public {
        uint256[] memory ids = new uint256[](3);
        uint256[] memory amounts = new uint256[](3);

        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        // Mint tokens
        for (uint256 i = 0; i < 3; i++) {
            erc1155Token.mint(account, ids[i], amounts[i], "");
        }

        // Sweep batch
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC1155Batch(address(erc1155Token), alice, ids, amounts, "");

        // Verify balances
        for (uint256 i = 0; i < 3; i++) {
            assertEq(erc1155Token.balanceOf(alice, ids[i]), amounts[i]);
            assertEq(erc1155Token.balanceOf(account, ids[i]), 0);
        }
    }

    function test_SweepERC1155BatchEmptyArrays() public {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        // Should work with empty arrays
        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC1155Batch(address(erc1155Token), alice, ids, amounts, "");
    }

    function test_RevertWhen_SweepERC1155BatchZeroToken() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC1155Batch(address(0), alice, ids, amounts, "");
    }

    function test_RevertWhen_SweepERC1155BatchZeroRecipient() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(alice);
        vm.expectRevert(SimpleAccount.ZeroAddress.selector);
        SimpleAccount(payable(account)).sweepERC1155Batch(address(erc1155Token), address(0), ids, amounts, "");
    }

    function test_RevertWhen_NotControllerSweepsERC1155Batch() public {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.prank(bob);
        vm.expectRevert();
        SimpleAccount(payable(account)).sweepERC1155Batch(address(erc1155Token), bob, ids, amounts, "");
    }

    function test_OnERC1155Received() public view {
        bytes4 selector = SimpleAccount(payable(account)).onERC1155Received(address(this), address(this), 1, 100, "");
        assertEq(selector, IERC1155Receiver.onERC1155Received.selector);
    }

    function test_OnERC1155BatchReceived() public view {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);

        bytes4 selector =
            SimpleAccount(payable(account)).onERC1155BatchReceived(address(this), address(this), ids, amounts, "");
        assertEq(selector, IERC1155Receiver.onERC1155BatchReceived.selector);
    }

    // Additional Succession Tests for Coverage
    function test_MultipleAccountsAfterSuccession() public {
        // Alice creates multiple accounts
        vm.startPrank(alice);
        address account2 = accountFactory.createAccount();
        address account3 = accountFactory.createAccount();
        vm.stopPrank();

        // Fund all accounts
        vm.deal(account, 10 ether);
        vm.deal(account2, 20 ether);
        vm.deal(account3, 30 ether);

        // Setup succession
        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry).setupSimplePolicy(bob, SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        // Execute succession
        vm.warp(block.timestamp + 181 days);
        vm.prank(bob);
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Bob controls all accounts
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), bob);
        assertEq(SimpleAccount(payable(account2)).getCurrentNFTController(), bob);
        assertEq(SimpleAccount(payable(account3)).getCurrentNFTController(), bob);

        // Bob can sweep from all
        vm.startPrank(bob);
        SimpleAccount(payable(account)).sweepAllNative();
        SimpleAccount(payable(account2)).sweepAllNative();
        SimpleAccount(payable(account3)).sweepAllNative();
        vm.stopPrank();

        assertEq(bob.balance, 160 ether); // Initial 100 + 10 + 20 + 30
    }

    function test_GetTokenBalanceZeroAddress() public {
        vm.expectRevert();
        assertEq(SimpleAccount(payable(account)).getTokenBalance(address(0)), 0);
    }

    function test_SupportsInterfaceReturnsFalse() public view {
        SimpleAccount acc = SimpleAccount(payable(account));

        // Random interface should return false
        assertFalse(acc.supportsInterface(0x12345678));
    }

    // Reentrancy Test for Coverage
    function test_ReentrancyProtectionOnSweepNative() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(account);
        vm.deal(account, 10 ether);

        // Transfer NFT to attacker so it can try to reenter
        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        vm.prank(alice);
        SimpleSuccessionRegistry(registry)
            .setupSimplePolicy(address(attacker), SimpleSuccessionRegistry.SimpleWaitPeriod.SIX_MONTHS);

        vm.warp(block.timestamp + 181 days);
        vm.prank(address(attacker));
        SimpleSuccessionRegistry(registry).executeSuccession();

        // Attacker tries to reenter
        vm.expectRevert(); // ReentrancyGuard should prevent
        attacker.attack();
    }

    // Fuzz Tests for Additional Coverage
    function testFuzz_SweepNativeAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < 1000000 ether);
        vm.deal(account, amount);

        uint256 sweepAmount = amount / 2;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepNative(alice, sweepAmount);

        assertEq(alice.balance - 100 ether, sweepAmount); // Alice started with 100 ether
        assertEq(account.balance, amount - sweepAmount);
    }

    function testFuzz_SweepERC20Amounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        token.mint(account, amount);

        uint256 sweepAmount = amount / 2;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC20(address(token), alice, sweepAmount);

        assertEq(token.balanceOf(alice), sweepAmount);
        assertEq(token.balanceOf(account), amount - sweepAmount);
    }

    function testFuzz_ERC1155Amounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        erc1155Token.mint(account, 1, amount, "");

        uint256 sweepAmount = amount / 2;

        vm.prank(alice);
        SimpleAccount(payable(account)).sweepERC1155(address(erc1155Token), alice, 1, sweepAmount, "");

        assertEq(erc1155Token.balanceOf(alice, 1), sweepAmount);
        assertEq(erc1155Token.balanceOf(account, 1), amount - sweepAmount);
    }
}

// ============ HELPER CONTRACTS ============

contract RevertingReceiver {
    receive() external payable {
        revert("No ETH accepted");
    }
}

contract ReentrancyAttacker {
    address public target;
    bool public attacking;

    constructor(address _target) {
        target = _target;
    }

    receive() external payable {
        if (attacking) {
            attacking = false;
            // Try to reenter
            SimpleAccount(payable(target)).sweepNative(address(this), 1 ether);
        }
    }

    function attack() external {
        attacking = true;
        SimpleAccount(payable(target)).sweepNative(address(this), 1 ether);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

// ============ MOCK CONTRACTS ============

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
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

        // Call receiver
        if (to.code.length > 0) {
            bytes4 retval = IERC721Receiver(to).onERC721Received(msg.sender, address(this), tokenId, "");
            require(retval == IERC721Receiver.onERC721Received.selector, "Invalid receiver");
        }
    }
}

contract MockERC1155 {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    string public name;
    string public symbol;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory) external {
        balanceOf[to][id] += amount;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external {
        balanceOf[from][id] -= amount;
        balanceOf[to][id] += amount;

        // Call receiver if contract
        if (to.code.length > 0) {
            bytes4 retval = IERC1155Receiver(to).onERC1155Received(msg.sender, from, id, amount, data);
            require(retval == IERC1155Receiver.onERC1155Received.selector, "Invalid receiver");
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        require(ids.length == amounts.length, "Length mismatch");

        for (uint256 i = 0; i < ids.length; i++) {
            balanceOf[from][ids[i]] -= amounts[i];
            balanceOf[to][ids[i]] += amounts[i];
        }

        // Call receiver if contract
        if (to.code.length > 0) {
            bytes4 retval = IERC1155Receiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, data);
            require(retval == IERC1155Receiver.onERC1155BatchReceived.selector, "Invalid receiver");
        }
    }
}
