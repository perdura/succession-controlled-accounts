// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseTest.t.sol";

contract RegistryFactoryTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Constructor ============

    function test_RevertWhen_ConstructorZeroImplementation() public {
        vm.expectRevert();
        new RegistryFactory(address(0), address(nft));
    }

    function test_RevertWhen_ConstructorZeroControllerNFT() public {
        vm.expectRevert();
        new RegistryFactory(address(registryImpl), address(0));
    }

    // ============ Registry Creation ============

    function test_CreateRegistry() public {
        vm.startPrank(alice);
        nft.mint();

        address registry = registryFactory.createRegistry();

        assertNotEq(registry, address(0));
        assertEq(registryFactory.userRegistry(alice), registry);
        assertEq(SimpleSuccessionRegistry(registry).owner(), alice);

        vm.stopPrank();
    }

    function test_RegistryAutoAuthorization() public {
        vm.startPrank(alice);
        nft.mint();

        address registry = registryFactory.createRegistry();

        assertTrue(nft.isAuthorizedRegistry(alice, registry));

        vm.stopPrank();
    }

    function test_RevertWhen_NoControllerNFT() public {
        vm.prank(alice);
        vm.expectRevert(RegistryFactory.NoControllerNFT.selector);
        registryFactory.createRegistry();
    }

    function test_RevertWhen_CreatingSecondRegistry() public {
        vm.startPrank(alice);
        nft.mint();

        registryFactory.createRegistry();

        vm.expectRevert(RegistryFactory.RegistryAlreadyExists.selector);
        registryFactory.createRegistry();

        vm.stopPrank();
    }

    // ============ Registry Tracking ============

    function test_RegistryCount() public {
        assertEq(registryFactory.getRegistryCount(), 0);

        vm.prank(alice);
        nft.mint();
        vm.prank(alice);
        registryFactory.createRegistry();

        assertEq(registryFactory.getRegistryCount(), 1);

        vm.prank(bob);
        nft.mint();
        vm.prank(bob);
        registryFactory.createRegistry();

        assertEq(registryFactory.getRegistryCount(), 2);
    }

    function test_GetRegistriesPaginated() public {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;

        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(users[i]);
            nft.mint();
            vm.prank(users[i]);
            registryFactory.createRegistry();
        }

        address[] memory registries = registryFactory.getRegistriesPaginated(0, 2);
        assertEq(registries.length, 2);

        registries = registryFactory.getRegistriesPaginated(2, 2);
        assertEq(registries.length, 1);
    }

    function test_RevertWhen_InvalidPageSize() public {
        vm.expectRevert(RegistryFactory.InvalidPageSize.selector);
        registryFactory.getRegistriesPaginated(0, 1001);
    }

    function test_UserRegistryMapping() public {
        assertEq(registryFactory.userRegistry(alice), address(0));

        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        address registry = registryFactory.createRegistry();

        assertEq(registryFactory.userRegistry(alice), registry);
    }

    // ============ Pause Functionality ============

    function test_FactoryPausing() public {
        vm.prank(deployer);
        registryFactory.setPaused(true);

        assertTrue(registryFactory.paused());

        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        vm.expectRevert(RegistryFactory.Paused.selector);
        registryFactory.createRegistry();

        vm.prank(deployer);
        registryFactory.setPaused(false);

        vm.prank(alice);
        registryFactory.createRegistry();
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(alice);
        vm.expectRevert();
        registryFactory.setPaused(true);
    }

    // ============ View Functions ============

    function test_GetControllerNFT() public view {
        assertEq(registryFactory.getControllerNFT(), address(nft));
    }

    function test_GetImplementation() public view {
        assertEq(registryFactory.getImplementation(), address(registryImpl));
    }
}

contract AccountFactoryTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    // ============ Constructor ============

    function test_RevertWhen_ConstructorZeroImplementation() public {
        vm.expectRevert();
        new AccountFactory(address(0), address(nft));
    }

    function test_RevertWhen_ConstructorZeroControllerNFT() public {
        vm.expectRevert();
        new AccountFactory(address(accountImpl), address(0));
    }

    // ============ Account Creation ============

    function test_CreateAccount() public {
        vm.startPrank(alice);
        nft.mint();

        address account = accountFactory.createAccount();

        assertNotEq(account, address(0));
        assertEq(SimpleAccount(payable(account)).getOriginalHolder(), alice);
        assertEq(SimpleAccount(payable(account)).getCurrentNFTController(), alice);

        vm.stopPrank();
    }

    function test_CreateMultipleAccounts() public {
        vm.startPrank(alice);
        nft.mint();

        address account1 = accountFactory.createAccount();
        address account2 = accountFactory.createAccount();
        address account3 = accountFactory.createAccount();

        assertNotEq(account1, account2);
        assertNotEq(account2, account3);
        assertNotEq(account1, account3);

        address[] memory accounts = accountFactory.getUserAccounts(alice);
        assertEq(accounts.length, 3);
        assertEq(accounts[0], account1);
        assertEq(accounts[1], account2);
        assertEq(accounts[2], account3);

        vm.stopPrank();
    }

    function test_RevertWhen_NoControllerNFT() public {
        vm.prank(alice);
        vm.expectRevert(AccountFactory.NoControllerNFT.selector);
        accountFactory.createAccount();
    }

    function test_AccountLimit() public {
        vm.startPrank(alice);
        nft.mint();

        uint256 maxAccounts = accountFactory.getMaxAccountsPerUser();

        for (uint256 i = 0; i < maxAccounts; i++) {
            accountFactory.createAccount();
        }

        vm.expectRevert(AccountFactory.AccountLimitExceeded.selector);
        accountFactory.createAccount();

        vm.stopPrank();
    }

    // ============ Account Tracking ============

    function test_GetUserAccountCount() public {
        vm.startPrank(alice);
        nft.mint();

        assertEq(accountFactory.getUserAccountCount(alice), 0);

        accountFactory.createAccount();
        assertEq(accountFactory.getUserAccountCount(alice), 1);

        accountFactory.createAccount();
        assertEq(accountFactory.getUserAccountCount(alice), 2);

        vm.stopPrank();
    }

    function test_GetAccountsPaginated() public {
        vm.startPrank(alice);
        nft.mint();

        for (uint256 i = 0; i < 5; i++) {
            accountFactory.createAccount();
        }
        vm.stopPrank();

        address[] memory accounts = accountFactory.getAccountsPaginated(0, 3);
        assertEq(accounts.length, 3);

        accounts = accountFactory.getAccountsPaginated(3, 3);
        assertEq(accounts.length, 2);
    }

    function test_GetAccountsPaginated_EmptyRange() public view {
        address[] memory accounts = accountFactory.getAccountsPaginated(0, 0);
        assertEq(accounts.length, 0);
    }

    function test_RevertWhen_InvalidPageSize() public {
        vm.expectRevert(AccountFactory.InvalidPageSize.selector);
        accountFactory.getAccountsPaginated(0, 1001);
    }

    function test_GetAccountCount() public {
        assertEq(accountFactory.getAccountCount(), 0);

        vm.prank(alice);
        nft.mint();
        vm.prank(alice);
        accountFactory.createAccount();

        assertEq(accountFactory.getAccountCount(), 1);

        vm.prank(bob);
        nft.mint();
        vm.prank(bob);
        accountFactory.createAccount();

        assertEq(accountFactory.getAccountCount(), 2);
    }

    // ============ Pause Functionality ============

    function test_FactoryPausing() public {
        vm.prank(deployer);
        accountFactory.setPaused(true);

        assertTrue(accountFactory.paused());

        vm.prank(alice);
        nft.mint();

        vm.prank(alice);
        vm.expectRevert(AccountFactory.Paused.selector);
        accountFactory.createAccount();

        vm.prank(deployer);
        accountFactory.setPaused(false);

        vm.prank(alice);
        accountFactory.createAccount();
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(alice);
        vm.expectRevert();
        accountFactory.setPaused(true);
    }

    // ============ View Functions ============

    function test_GetControllerNFT() public view {
        assertEq(accountFactory.getControllerNFT(), address(nft));
    }

    function test_GetImplementation() public view {
        assertEq(accountFactory.getImplementation(), address(accountImpl));
    }

    function test_GetMaxAccountsPerUser() public view {
        assertEq(accountFactory.getMaxAccountsPerUser(), 25);
    }
}
