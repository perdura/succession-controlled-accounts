// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/reference/ControllerNFT.sol";
import "../contracts/reference/SimpleSuccessionRegistry.sol";
import "../contracts/reference/vault/SimpleAccount.sol";
import "../contracts/reference/RegistryFactory.sol";
import "../contracts/reference/vault/AccountFactory.sol";

abstract contract BaseTest is Test {
    // Core contracts
    ControllerNFT public nft;
    RegistryFactory public registryFactory;
    AccountFactory public accountFactory;

    // Implementation contracts
    SimpleSuccessionRegistry public registryImpl;
    SimpleAccount public accountImpl;

    // Test accounts
    address public deployer;
    address public alice;
    address public bob;
    address public charlie;
    address public david;
    address public eve;
    address public attacker;

    function setUp() public virtual {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");
        david = makeAddr("david");
        eve = makeAddr("eve");
        attacker = makeAddr("attacker");

        vm.deal(deployer, 1000 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(david, 100 ether);
        vm.deal(eve, 100 ether);
        vm.deal(attacker, 100 ether);

        vm.startPrank(deployer);

        nft = new ControllerNFT();

        registryImpl = new SimpleSuccessionRegistry();
        accountImpl = new SimpleAccount();

        registryFactory = new RegistryFactory(address(registryImpl), address(nft));

        accountFactory = new AccountFactory(address(accountImpl), address(nft));

        nft.setTrustedFactory(address(registryFactory), true);

        vm.stopPrank();

        // Start at day 1 to avoid timestamp edge cases
        vm.warp(1 days);
    }
}
