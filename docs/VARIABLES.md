# Documentation Variables

> **Single source of truth for values used across documentation**

> **Last Updated:** 2025-11-05

---

## Project Identifiers

**EIP Number:** `XXXX` (pending assignment)  
**Status:** `Draft`  
**Repository:** `github.com/perdura/succession-controlled-accounts`  
**Author:** `@tian0` / `tian0@perdura.xyz`  
**Magicians Discussion:** `link-when-available`

---

## Test Metrics

**Test Count:** `209`
```bash
# Verify: forge test --list 2>/dev/null | grep -c "^test"
```

**Coverage (Reference Implementation Only):**
- Lines: `97.0%` (322/332)
- Statements: `94.9%` (374/394)  
- Branches: `84.9%` (62/73)
- Functions: `100%` (70/70)

**Coverage (All Contracts):**
- Lines: `93.0%` (437/470)
- Statements: `91.6%` (459/501)
- Functions: `95.3%` (101/106)
```bash
# Verify: forge coverage --ir-minimum
# Then manually sum: ControllerNFT, NFTLinked, RegistryFactory, SimpleSuccessionRegistry, AccountFactory, SimpleAccount
```

---

## Gas Benchmarks

| Operation | Gas Cost | vs Full Deploy | Full Cost |
|-----------|----------|----------------|-----------|
| **Registry Deploy (via Factory)** | ~272k | 80.1% savings | ~1.37M |
| **Account Deploy (via Factory)** | ~266k | 81.5% savings | ~1.44M |
| **Check-In** | ~9k | - | - |
| **Execute Succession** | ~123k | - | - |
| **Mint Controller NFT** | ~186k | - | - |

**Average Savings:** ~81%
```bash
# Verify: forge test --gas-report
```

---

## Contract Constants

**MAX_INHERITED_TOKENS:** `8`  
*Location: `contracts/reference/ControllerNFT.sol`*

**MAX_ACCOUNTS_PER_USER:** `25`  
*Location: `contracts/reference/vault/AccountFactory.sol`*

**Wait Period Options:**
- `SIX_MONTHS`: 180 days
- `ONE_YEAR`: 365 days  
*Location: `contracts/reference/SimpleSuccessionRegistry.sol`*

---

## Quick Update Commands
```bash
# Find all references to a value
grep -r "XXXX" --include="*.md" .
grep -r "Draft" --include="*.md" .
grep -r "209 tests" --include="*.md" .
grep -r "97.0%\|97%" --include="*.md" .
grep -r "272k\|266k\|81%" --include="*.md" .
```
