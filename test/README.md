# Test Suite

**209 comprehensive tests** covering all contract functionality, security scenarios, edge cases, and integration flows.

**Terminology Note:** This document uses "successor" to describe the person designated to gain control after succession conditions are met. The reference implementation code uses `beneficiary` as the variable name for this address. These terms refer to the same concept.

---

## Quick Start
```bash
# Run all tests
forge test

# Run with detailed output
forge test -vvv

# Run specific test file
forge test --match-path test/ControllerNFT.t.sol

# Generate coverage report
forge coverage

# Gas usage report
forge test --gas-report
```
---

## Test Organization

### Setup

**BaseTest.t.sol** - Generalized setup, infrastructure deployment

### Core Components

**ControllerNFT.t.sol** - Tests minting (one per address), burning (can't burn originally minted token), registry authorization, and inheritance tracking (MAX_INHERITED_TOKENS = 8 limit).

**NFTLinkedTests.t.sol** - Tests the INFTLinked pattern. The critical test: when the NFT transfers via succession, does `getCurrentNFTController()` automatically return the new owner? Also verifies that `onlyController` modifier properly reverts for non-controllers.

**SimpleSuccessionRegistry.t.sol** - Policy setup (`setupSimplePolicy`), check-ins (resets timer), `executeSuccession()` calls (transfers NFT to successor), and spam clearing (burns unwanted inherited NFTs to make space).

**SimpleAccount.t.sol** - Asset sweeps (Native, ERC20, ERC721, ERC1155), access control verification after succession, and ERC721/ERC1155 receiver hooks.

### Security & Edge Cases

**SecurityTests.t.sol** - Reentrancy, access control, inheritance griefing, factory trust

**EdgeCaseTests.t.sol** - Zero addresses, max values, empty inputs, burned tokens, gas usage

### Integration & Deployment

**IntegrationTests.t.sol** - End-to-end succession flows, multi-account management

**FactoryTests.t.sol** - Registry/account deployment, auto-authorization, pause functionality

---

## Test Categories

**Functional Testing:**
- Happy path scenarios (standard user flows)
- Error conditions (reverts with correct errors)
- State transitions (check-ins, succession transfers, burns)

**Security Testing:**
- Access control (onlyController, onlyOwner, factory-only)
- Reentrancy protection (ReentrancyGuard on all state changes)
- Input validation (zero addresses, bounds checks)
- Succession griefing protection (MAX_INHERITED_TOKENS, partial transfers)

**Integration Testing:**
- Multi-component workflows (NFT + Registry + Account)
- Factory deployment flows (clone + initialize + authorize)
- Succession scenarios (inactivity, transfer, and automatic control recognition)

**Edge Case Testing:**
- Boundary values (0, type(uint256).max)
- Empty inputs ([], empty arrays)
- Burned tokens (access control after burn)
- Storage limits (succession capacity)
- Gas Usage Tracking (single and chained successions)

---

## Coverage Report

**Reference Implementation Coverage: 97.0% lines, 94.9% statements, 100% functions**

The table below shows coverage including test helper contracts. For reference implementation code coverage only, see breakdown:

| Contract | Lines | Statements | Branches | Functions |
|----------|-------|------------|----------|-----------|
| **Reference Implementation** | | | | |
| ControllerNFT.sol | 97.18% (69/71) | 95.95% (71/74) | 87.50% (14/16) | 100.00% (16/16) |
| NFTLinked.sol | 100.00% (19/19) | 100.00% (23/23) | 100.00% (3/3) | 100.00% (6/6) |
| RegistryFactory.sol | 95.35% (41/43) | 93.88% (46/49) | 90.00% (9/10) | 100.00% (9/9) |
| SimpleSuccessionRegistry.sol | 97.65% (83/85) | 94.74% (108/114) | 80.00% (16/20) | 100.00% (11/11) |
| AccountFactory.sol | 95.65% (44/46) | 94.00% (47/50) | 90.00% (9/10) | 100.00% (11/11) |
| SimpleAccount.sol | 97.06% (66/68) | 94.05% (79/84) | 78.57% (11/14) | 100.00% (17/17) |
| **Subtotal (Reference)** | **97.0% (322/332)** | **94.9% (374/394)** | **84.9% (62/73)** | **100.00% (70/70)** |
| | | | | |
| **Test Helpers** | | | | |
| BaseTest.t.sol | 100.00% (24/24) | 100.00% (23/23) | - | 100.00% (1/1) |
| Other test contracts | 79.8% (91/114) | 73.8% (62/84) | 30.0% (6/20) | 85.71% (30/35) |
| | | | | |
| **Total (All Contracts)** | **93.0% (437/470)** | **91.6% (459/501)** | **73.1% (68/93)** | **95.3% (101/106)** |

**Reference Implementation Coverage:**
- **All 70 functions tested** (100% function coverage)
- 97.0% line coverage (322 of 332 lines)
- 94.9% statement coverage (374 of 394 statements)
- 84.9% branch coverage (62 of 73 branches)

**Uncovered areas:**

All reference implementation functions are tested (100% function coverage). The 10 uncovered lines (97.0% coverage) are:
- Constructor disable checks (2 lines) - implementation contracts prevent direct initialization by design
- Factory pause validation and pagination boundaries (4 lines) - defensive checks tested via revert paths
- ControllerNFT token array management (2 lines) - edge cases in storage handling
- SimpleAccount/Registry initializer guards (2 lines) - re-initialization protection

All critical succession logic and security paths are fully covered.

---

## Running Specific Test Suites
```bash
# Security tests only
forge test --match-path test/SecurityTests.t.sol -vv

# Integration tests with gas reports
forge test --match-path test/IntegrationTests.t.sol --gas-report

# All tests matching pattern
forge test --match-test test_MintFirstNFT -vv

# Run with specific fork (if needed)
forge test --fork-url $MAINNET_RPC_URL
```

---

## Test Utilities

**BaseTest.t.sol** provides shared test infrastructure:

**Test Accounts:**
- Pre-configured addresses: alice, bob, charlie, david, eve, attacker
- Pre-funded with 100-1000 ETH for gas

**Contract Setup:**
- Deployed core contracts: ControllerNFT, RegistryFactory, AccountFactory
- Deployed implementations: SimpleSuccessionRegistry, SimpleAccount
- Trusted factory authorization configured

**Event Declarations:**
- Common events for expectEmit assertions
- ControllerNFTMinted, SuccessionExecuted, RegistryCreated, AccountCreated

**Time Configuration:**
- Tests start at timestamp = 1 day (avoids zero timestamp issues)
- Use Foundry's vm.warp() for time manipulation in individual tests

**Usage:**
```solidity
contract MyTest is BaseTest {
    function testSuccession() public {
        // Test accounts pre-configured
        vm.prank(alice);
        nft.mint();
        
        // Factories already deployed and authorized
        address registry = registryFactory.createRegistry();
        
        // Time travel available via vm.warp()
        vm.warp(block.timestamp + 365 days);
    }
}
```

---

## Writing New Tests

When adding tests, ensure:

1. **Clear naming**: `test_functionName_scenario_expectedOutcome()`
```solidity
   function test_executeSuccession_afterWaitPeriod_succeeds() public
   function test_executeSuccession_tooEarly_reverts() public
```

2. **AAA pattern**: Arrange, Act, Assert
```solidity
   // Arrange - Setup policy with bob as successor
   vm.prank(alice);
   registry.setupSimplePolicy(bob, SimpleWaitPeriod.ONE_YEAR);
   
   // Act - Wait for inactivity period and execute succession
   vm.warp(block.timestamp + 365 days + 1);
   vm.prank(bob);
   registry.executeSuccession();
   
   // Assert - Verify bob now controls the NFT
   assertEq(nft.ownerOf(aliceTokenId), bob);
```

3. **Test both success and failure**: Every function should have happy path + revert tests

4. **Use descriptive revert messages**: Check for specific custom errors
```solidity
   vm.expectRevert(ISuccessionRegistry.TooEarly.selector);
```

5. **Variable naming consistency**: Use `beneficiary` in code (matches implementation), add comments clarifying "successor"
```solidity
   address beneficiary = bob; // Bob is Alice's successor
   registry.setupSimplePolicy(beneficiary, SimpleWaitPeriod.ONE_YEAR);
```

---

## CI/CD

Tests run automatically on:
- Every pull request
- Every commit to main branch

GitHub Actions workflow: `.github/workflows/tests.yml`

---

**Questions or issues?** Open an issue in the repository.

**Tian**, 2025