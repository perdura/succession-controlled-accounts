# Integration Guide for Succession-Controlled Accounts

> **Note:** Draft supporting material for EIP-XXXX. Subject to revision based on community feedback.

**Legal Notice:** This standard provides technical infrastructure only. Smart contract succession does not replace traditional estate planning or corporate governance requirements. For legal considerations, see [Security Considerations - Legal and Regulatory Risks](./SecurityConsiderations.md#legal-and-regulatory-considerations).

**Terminology Note:** This document uses "successor" to describe the person designated to gain control after succession conditions are met. The reference implementation code uses `beneficiary` as the variable name for this address. These terms refer to the same concept.

This guide helps developers integrate succession-controlled accounts into their protocols and contracts.

---

## Table of Contents

1. [For Smart Contract Developers](#for-smart-contract-developers)
2. [Common Integration Patterns](#example-integration-patterns)
3. [Testing Your Integration](#testing-your-integration)
4. [Best Practives](#best-practices)
5. [Support](#support)

---

## For Smart Contract Developers

### Detecting if User Has Controller NFT

```solidity
// Import from your installed package or local path
import "succession-controlled-accounts/interfaces/IControllerNFT.sol";

contract MyDApp {
    IControllerNFT public controllerNFT;
    
    // Check if user minted
    function checkUserHasMinted(address user) public view returns (bool) {
        return controllerNFT.hasMinted(user);
    }
    
    // Check if user has VALID controller (returns address(0) if burned)
    function getUserController(address user) public view returns (address) {
        return controllerNFT.getCurrentController(user);
    }

    // Get user's original token ID (may be burned if succession occurred)
    function getUserTokenId(address user) public view returns (uint256) {
        return controllerNFT.originalTokenId(user);
    }
    
    // Check if user can act on succession-controlled accounts
    function canUserAct(address user) public view returns (bool) {
        return controllerNFT.getCurrentController(user) != address(0);
    }
}
```

### Making Your Vault Succession-Compatible

To make any vault/contract succession-enabled, implement the INFTLinked pattern by inheriting from `NFTLinked`:
```solidity
import "succession-controlled-accounts/reference/NFTLinked.sol";

contract MyProtocolVault is NFTLinked {
    // Your vault logic here
    
    constructor() {
        // Don't initialize NFTLinked in constructor
    }
    
    // Initialize function for clone pattern
    function initialize(
        address _owner,
        address _controllerNFT
    ) external initializer {
        _initializeNFTLinking(_controllerNFT, _owner);
        // Your initialization logic
    }
    
    // Use onlyController for access control
    // The successor automatically gains access when the Controller NFT transfers
    function withdraw(uint256 amount) external onlyController {
        payable(getCurrentNFTController()).transfer(amount);
    }
    
    function emergencyPause() external onlyController {
        // Emergency functions
    }
}
```

**Key Points:**
- Inherit from `NFTLinked` to gain automatic succession capabilities
- Use `onlyController` modifier for access-controlled functions
- `getCurrentNFTController()` automatically recognizes the new controller after succession

### Implementing IControlledAccount

Full implementation for multi-asset vaults:

```solidity
import "succession-controlled-accounts/interfaces/IControlledAccount.sol";
import "succession-controlled-accounts/reference/NFTLinked.sol";

contract MyVault is NFTLinked, IControlledAccount {
    using SafeERC20 for IERC20;
    
    function initialize(address _owner, address _controllerNFT) external initializer {
        _initializeNFTLinking(_controllerNFT, _owner);
    }
    
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
    
    function sweepNative(address to, uint256 amount) external onlyController {
        uint256 amt = amount == type(uint256).max 
            ? address(this).balance 
            : amount;
        (bool sent, ) = to.call{value: amt}("");
        require(sent, "Transfer failed");
        emit SweptNative(to, amt);
    }
    
    function sweepERC20(address token, address to, uint256 amount)external onlyController {
        IERC20(token).safeTransfer(to, amount);
        emit SweptERC20(token, to, amount);
    }
    
    // Other sweep functions...
}
```

### Checking Controller Before Actions

```solidity
contract MyProtocol {
    IControllerNFT public controllerNFT;
    
    function performSensitiveAction(
        address vault,
        bytes calldata data
    ) external {
        // Get the vault's linked NFT and original holder
        INFTLinked linkedVault = INFTLinked(vault);
        address originalHolder = linkedVault.getOriginalHolder();
        
        // Check who currently controls the vault
        address currentController = controllerNFT.getCurrentController(originalHolder);
        
        require(msg.sender == currentController, "Not authorized");
        
        // Perform action
        (bool success, ) = vault.call(data);
        require(success, "Action failed");
    }
}
```

---

## Example Integration Patterns

### Pattern 1: Multi-Account Management
```solidity
contract SuccessionManager {
    IAccountFactory public accountFactory;
    IControllerNFT public controllerNFT;
    
    // Create multiple accounts for different purposes
    function setupMultipleAccounts() external returns (
        address personalVault,
        address businessVault,
        address trustVault
    ) {
        // Dual verification for minted and valid (not burned by a successor) NFT
        require(controllerNFT.hasMinted(msg.sender), "Must have Controller NFT");
        require(controllerNFT.getCurrentController(msg.sender) != address(0), "Must have VALID Controller NFT");
        
        personalVault = accountFactory.createAccount();
        businessVault = accountFactory.createAccount();
        trustVault = accountFactory.createAccount();
        
        // User can now fund each vault separately
        // All vaults are controlled by the same Controller NFT
        // Succession transfers control of all vaults automatically
    }
    
    // Sweep all accounts to one location
    function consolidateAssets(address destination) external {
        address[] memory accounts = accountFactory.getUserAccounts(msg.sender);
        
        for (uint i = 0; i < accounts.length; i++) {
            IControlledAccount account = IControlledAccount(accounts[i]);
            
            // Sweep all Native
            account.sweepAllNative();
            
            // Sweep common tokens
            account.sweepAllERC20(USDC);
            account.sweepAllERC20(DAI);
        }
    }
}
```

### Pattern 2: Gradual Asset Transfer
```solidity
// Allow successor to claim assets gradually over time
contract GradualReleaseVault is NFTLinked {
    uint256 public constant RELEASE_PERIOD = 365 days;
    uint256 public successionTimestamp;
    
    function getReleasableAmount() public view returns (uint256) {
        if (successionTimestamp == 0) return 0;
        
        uint256 elapsed = block.timestamp - successionTimestamp;
        if (elapsed >= RELEASE_PERIOD) return address(this).balance;
        
        uint256 totalBalance = address(this).balance;
        return (totalBalance * elapsed) / RELEASE_PERIOD;
    }
    
    function withdraw(uint256 amount) external onlyController {
        require(amount <= getReleasableAmount(), "Not yet released");
        payable(getCurrentNFTController()).transfer(amount);
    }
    
    // Called automatically when succession occurs (via hook in NFTLinked)
    function _onSuccession() internal override {
        successionTimestamp = block.timestamp;
    }
}
```

### Pattern 3: Emergency Override
```solidity
// Example of guardian-approved access pattern for NFTLinked account:
// Successor needs emergency access and must be approved by 2/3 guardians
// Note: The reference implementation uses time-based policies
// Alternative mplementations can add guardian logic
contract GuardianApprovedVault is NFTLinked {
    address[] public emergencyContacts;
    mapping(address => bool) public emergencyApprovals;
    
    function requestEmergencyAccess() external {
        require(isEmergencyContact(msg.sender), "Not authorized");
        emergencyApprovals[msg.sender] = true;
    }
    
    function emergencyWithdraw() external onlyController {
        // Require 2/3 emergency contacts to approve
        uint256 approvalCount = 0;
        for (uint i = 0; i < emergencyContacts.length; i++) {
            if (emergencyApprovals[emergencyContacts[i]]) {
                approvalCount++;
            }
        }
        
        require(approvalCount >= 2, "Insufficient emergency approvals");
        
        // Allow withdrawal
        payable(getCurrentNFTController()).transfer(address(this).balance);
    }
}
```

**Note:** This pattern shows how to add guardian approval logic. The reference implementation uses time-based policies without guardians. The minimal interface design enables implementations to add guardian requirements at the account level, while global approval (for all linked accounts) can be enabled at the registry level.

### Pattern 4: Managing Inherited Tokens

When users inherit Controller NFTs through succession, they may receive unwanted tokens. Since each address can only hold `MAX_INHERITED_TOKENS` (default: 8), users need to manage their token storage.
```solidity
// Check how many tokens a user currently holds
uint256[] memory userTokens = nft.getUserTokens(bob);
uint256 currentCount = userTokens.length;
uint256 maxTokens = nft.MAX_INHERITED_TOKENS();
uint256 availableSlots = maxTokens - currentCount;

// Before claiming succession, ensure sufficient space
if (availableSlots == 0) {
    // Burn one unwanted inherited token to make space
    // Important: Consolidate assets first
    // After burning, accounts controlled by that Controller NFT will have no valid controller
    // Cannot burn originally minted token (protected)
    uint256 originalToken = controllerNFT.originalTokenId(bob);
    
    // Make space for one more
    for (uint i = 0; i < bobsTokens.length; i++) {
        if (bobsTokens[i] != originalToken) {
            controllerNFT.burn(bobsTokens[i]);
            break; 
        }
    }
}

// Now claim succession
registry.executeSuccession();
```

**Important Notes:**
- Users CANNOT burn their originally minted token (protected in ControllerNFT.sol)
- Users CAN burn inherited tokens to free space
- Users SHOULD consolidate assets from inherited accounts after succession
- Burning is permanent and cannot be undone
- Only the token owner can burn tokens they hold
- Burning an inherited token doesn't affect the accounts it controlled, but those accounts will no longer recognize a controller

---

## Testing Your Integration

### Unit Test Example
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "succession-controlled-accounts/reference/ControllerNFT.sol";
import "succession-controlled-accounts/reference/vault/SimpleAccount.sol";

contract IntegrationTest is Test {
    ControllerNFT nft;
    SimpleAccount account;
    
    address alice = address(0x1);
    address bob = address(0x2);
    
    function setUp() public {
        nft = new ControllerNFT();
        
        // Deploy account implementation
        SimpleAccount accountImpl = new SimpleAccount();
        
        // Deploy account clone for Alice
        account = SimpleAccount(payable(Clones.clone(address(accountImpl))));
        account.initialize(alice, address(nft));
        
        // Mint NFT for Alice
        vm.prank(alice);
        nft.mint();
    }
    
    function testSuccessionTransfersControl() public {
        // Fund account
        vm.deal(address(account), 10 ether);
        
        // Alice can withdraw
        vm.prank(alice);
        account.sweepNative(alice, 1 ether);
        assertEq(alice.balance, 1 ether);
        
        // Alice needs to clone succession registry AND set up succession policy
        // When succession policy conditions are met, simulate succession:
        // Bob calls executeSuccession() and NFT transfers to Bob
        // (This happens via authorized registry)
        // For testing, use internal _transfer if exposed, or test via custom registry
        
        // After succession, Bob can withdraw
        vm.prank(bob);
        account.sweepAllNative();
        assertEq(bob.balance, 9 ether);
    }
}
```

---

## Best Practices

### ✓ DO:
- Always check `hasMinted()` before assuming user has Controller NFT
- Use `getCurrentController()` for access control, not stored addresses
- Listen for `SuccessionExecuted` events to update UI
- Show clear succession status indicators in UI
- Provide check-in reminders to users (for time-based policies)
- Display inherited token count to help users manage token limits
- Verify account addresses before sending assets

### ✗ DON'T:
- Don't store controller address - always query from Controller NFT via `getCurrentController()`
- Don't assume NFT ownership is permanent (succession can transfer it)
- Don't send assets to Controller NFT/Registry/Factory addresses (only to Controlled Accounts)
- Don't implement succession logic yourself - use standard registries following ISuccessionRegistry
- Don't burn the originally minted token (ControllerNFT prevents this)

---

### Frontend Integration Notes

While this guide focuses on smart contract integration, frontend developers should:
- Query `hasMinted()` and `getCurrentController()` to display succession status
- Listen for `SuccessionExecuted` events to update UI state
- Show clear succession status indicators
- Provide check-in reminders for time-based policies

Specific frontend implementation patterns are outside the scope of this guide.

---

## Support

- **Specification**: [Draft Specification](./eip-succession-controlled-accounts.md)
- **Issues**: [GitHub Issues](https://github.com/perdura/succession-controlled-accounts/issues)
- **Discussions**: [Ethereum Magicians Thread](link-when-available)

---

Happy building!