# Use Cases - Succession-Controlled Accounts

> **Note:** Draft supporting material for EIP-XXXX. Examples subject to expansion based on community feedback.

**Terminology Note:** This document uses "successor" to describe the person designated to gain control after succession conditions are met. The reference implementation code uses `beneficiary` as the variable name for this address. These terms refer to the same concept.

---

## About This Document

This document demonstrates use cases for the Succession-Controlled Accounts standard. Because the standard uses minimal, flexible interfaces, this document shows two types of implementations:

### Reference Implementation (Available Now)
- **Policy Type:** Time-based inactivity with proof-of-life check-ins
- **Status:** Complete and tested (209 tests, 97% coverage) - not audited
- **Use When:** 6-12 month wait periods are acceptable
- **Deployment:** For testnet experimentation only; requires professional audit before mainnet use

Uses: `registry.setupSimplePolicy(beneficiary, waitPeriod)`

### Alternative Implementations (Conceptual)
- **Policy Types:** Guardian-approved, oracle-triggered, DAO-voted, etc.
- **Status:** Valid implementations of ISuccessionRegistry interface (not yet built)
- **Use When:** Different policy requirements needed
- **Shown in this doc:** One guardian-approved example (Use Case 8)

**What "Alternative Implementation" means:** These are conceptual examples showing what the standard enables. They would require:
- Custom registry contract implementing ISuccessionRegistry
- Policy-specific coordination mechanisms (guardians, oracles, etc.)
- Professional security audit
- Community review and testing

**Why show alternatives?** The standard's minimal (IControllerNFT, INFTLinked, ISuccessionRegistry) interfaces intentionally enable diverse policy types. This document includes one guardian-approved example to demonstrate the standard's flexibility and inspire alternative implementations.

**Want to use this now?** The reference implementation is ready for testnet deployment and experimentation.

**Do not use on mainnet with significant value without a professional security audit.** Alternative implementations require custom development following the standard plus their own security audits.

---

## Legal Notice

**This standard provides technical infrastructure for digital asset succession. It does not constitute legal advice or create legally binding arrangements.**

Smart contract succession mechanisms do not replace traditional estate planning requirements. Users implementing any of the use cases described below should consult qualified legal professionals regarding:
- Estate planning and inheritance laws
- Corporate governance requirements  
- Tax implications
- Regulatory compliance

Technical implementation does not guarantee legal recognition or enforceability. 

**For comprehensive legal and regulatory analysis, see [Security Considerations - Legal and Regulatory Risks](./SecurityConsiderations.md#legal-and-regulatory-considerations).**

---

## Table of Contents

- [About This Document](#about-this-document)
  - [Reference Implementation (Available Now)](#reference-implementation-available-now)
  - [Alternative Implementations (Conceptual)](#alternative-implementations-conceptual)
- [Legal Notice](#legal-notice)
- [Core Use Cases](#core-use-cases)
  - [Use Case 1: Personal Cryptocurrency Inheritance](#use-case-1-personal-cryptocurrency-inheritance)
  - [Use Case 2: Multi-Generational Wealth Transfer](#use-case-2-multi-generational-wealth-transfer)
    - [Critical Issue: Unclaimed Succession](#critical-issue-unclaimed-succession)
  - [Use Case 3: Split Estate Between Multiple Successors](#use-case-3-split-estate-between-multiple-successors)
  - [Use Case 4: Startup Company Treasury](#use-case-4-startup-company-treasury)
  - [Use Case 5: Governance Token Vesting with Succession](#use-case-5-governance-token-vesting-with-succession)
  - [Use Case 6: E-Commerce Crypto Payments](#use-case-6-e-commerce-crypto-payments)
- [Advanced Use Cases](#advanced-use-cases)
  - [Use Case 7: Trust Fund for Minor Child](#use-case-7-trust-fund-for-minor-child)
  - [Use Case 8: DAO Treasury Succession](#use-case-8-dao-treasury-succession)
- [Summary](#summary)
---

## Core Use Cases

### Use Case 1: Personal Cryptocurrency Inheritance

**Scenario:**
Alice (45, tech professional) has accumulated crypto assets:
- 100 ETH
- 50,000 USDC
- Various DeFi positions (Aave, Compound)
- NFT collection (CryptoPunks, Art Blocks)

**Problem:**
- If something happens to Alice, her family cannot access these assets
- Her spouse Bob is crypto-literate but doesn't know all her holdings
- Private keys cannot be shared without giving away immediate control

**Solution:**
```solidity
// Alice's Setup
1. Mint Controller NFT
2. Create Succession Registry
   - Successor: Bob (spouse) // Stored as 'beneficiary' in code
   - Policy: 1 year inactivity (time-based)
3. Create Vault (implements INFTLinked)
4. Transfer all assets to vault
5. Check in quarterly (Calendar reminder)

// Assets in Vault:
- 10 ETH
- 50,000 USDC
- aETH (Aave deposits earning yield)
- cDAI (Compound deposits earning yield)
- CryptoPunk #1234
- Art Blocks pieces
```

**Workflow:**
1. Alice checks in every 3 months (resets timer)
2. If Alice becomes incapacitated or passes away
3. After 1 year of no check-ins
4. Bob calls `executeSuccession()`
5. Bob gains control of the vault
6. Bob sweeps all assets (and continued earning yield)

**Benefits:**
- Bob doesn't need Alice's private keys
- Assets earn yield during the entire time
- DeFi positions transfer atomically
- Works globally, regardless of jurisdiction
- One-time setup: NFT, ~272k for registry, ~266k per account
- Check-ins: ~9k gas each
- Succession claim: ~123k gas (worst-case single token)

**Note:** Gas costs from actual test execution. Succession claim represents worst-case measurement (successor with 0 tokens). Other operations represent typical usage patterns. Actual costs vary based on state and network conditions.

---

### Use Case 2: Multi-Generational Wealth Transfer

**Scenario:**
Alice's successor is Bob (son), Bob's successor is Charlie (grandson)

**Success Flow:**
```solidity
// Generation 1: Alice's Setup
alice_registry.setupSimplePolicy(bob, ONE_YEAR);
alice_vaults: 100 ETH

// Generation 2: Bob's Setup  
bob_registry.setupSimplePolicy(charlie, ONE_YEAR);
bob_vaults: 50 ETH

// Succession Flow:
1. Alice inactive for 1 year
2. Bob claims: alice_registry.executeSuccession()
3. Bob consolidates alice_vaults (bob_vaults hold 150 ETH total)
4. Bob burns Alice's NFT (frees storage)
5. Bob inactive for 1 year
6. Charlie claims: bob_registry.executeSuccession()
7. Charlie controls all 150 ETH
```

**Benefits:**
- Three-generation succession without coordination
- Each generation maintains control during lifetime
- Assets automatically flow to final successor

**Note:** This use case demonstrates the INFTLinked pattern's power - vaults automatically recognize the new controller when the NFT transfers, with no state changes needed in the vault contracts.

---

#### Critical Issue: Unclaimed Succession

**Problem:** If Bob dies without claiming Alice's estate, Charlie loses access to it forever.

**Failure Scenario:**
```
1. When Alice inactive, Bob is eligible to claim
2. Bob doesn't claim (tax reasons, blacklisted assets, or waiting)
3. Bob dies inactive
4. Charlie claims Bob's NFT
5. Charlie CANNOT claim Alice's NFT (Bob never claimed it)
6. Alice's estate orphaned permanently
```

**Why This Design:**
The reference implementation restricts `executeSuccession()` to designated successor only (code: `msg.sender == policy.beneficiary`).

**Trade-offs:**
- Protects successors from unwanted inheritance (tax liability, sanctions)
- Successor choice (can decline problematic estates)
- ✗ Risk of orphaned estates if successor doesn't claim before dying
- ✗ No automatic multi-generational fallback

**Solutions:**

**1. Prompt Claiming (Best Practice):**
```solidity
// Bob must claim promptly after eligibility
alice_registry.executeSuccession(); // Bob claims within weeks, not years
// Later, Charlie gets both
bob_registry.executeSuccession();
alice_registry.executeSuccession(); // Alice's NFT now transfers from Bob to Charlie
```

**2. Clean Assets Only:**
- Don't put problematic/blacklisted assets in succession vaults
- Successor should want to claim

**3. Communication/Updates:**
- Inform successors: "Claim my estate promptly if you want it to pass to your heirs"
- Document estates in off-chain instructions
- Update successor designations accordingly

**4. Parallel Legal Planning:**
- Traditional will: "Bob's estate includes right to claim Alice's Controller NFT"
- Legal executor can claim on Bob's behalf

**5. Alternative Implementation (Not in Reference):**
```solidity
// Contingent successor pattern (not in reference implementation)
policy: {
    primary: bob,
    contingent: charlie,
    gracePeriod: 180 days
}
// If Bob doesn't claim within 180 days, Charlie can claim directly
```

**Recommended:**
- Choose successors with significant age gaps (reduces overlap risk)
- Successors should claim within 30-90 days of eligibility
- Use parallel legal structures for complex multi-generational estates

**Note:** The reference implementation uses time-based policies. Alternative implementations could add contingent successors, permissionless execution after extended periods, or other multi-generational fallback mechanisms.

---

### Use Case 3: Split Estate Between Multiple Successors

**Scenario:**
Alice wants to split assets between:
- 50% to spouse (Bob)
- 30% to daughter (Diana)
- 20% to son (Sam)

**Solution:**
```solidity
// Create separate accounts for each successor
vault_bob = accountFactory.createAccount();
vault_diana = accountFactory.createAccount();
vault_sam = accountFactory.createAccount();

// Fund according to split
vault_bob:   50 ETH (50%)
vault_diana: 30 ETH (30%)
vault_sam:   20 ETH (20%)

// Single registry, different accounts
registry.setupSimplePolicy(multiSigSuccessor, ONE_YEAR);

// MultiSig Contract Logic:
// - Bob, Diana, Sam are multisig signers
// - They coordinate to sweep each vault
// - Or: Use custom contract with built-in splitting logic
```

**Alternative Approach:**
```solidity
// Separate registries for each successor:
// Note: Each registry requires an NFT
//       Each wallet can only mint one NFT
// Alice uses 3 separate wallets to mint 3 NFTs and creates 3 registries

registry_bob.setupSimplePolicy(bob, ONE_YEAR);
vault_bob: 50 ETH

registry_diana.setupSimplePolicy(diana, ONE_YEAR);
vault_diana: 30 ETH

registry_sam.setupSimplePolicy(sam, ONE_YEAR);
vault_sam: 20 ETH

// Each successor claims independently
```

**Benefits:**
- Clear asset allocation
- Independent claiming
- No successor coordination needed
- Flexible percentages

---

### Use Case 4: Startup Company Treasury

**Scenario:**
TechCorp (startup) has a $2M treasury:
- 1.5M USDC
- $500K in governance tokens
- Controlled by CEO (Alice)

**Problem:**
- If CEO is hit by a bus, company cannot access funds
- Board needs assurance of treasury continuity
- Don't want CEO to have unilateral permanent control

**Solution: Time-Based (Reference Implementation)**
```solidity
// Company Setup
controller_nft.mint(); // CEO mints NFT
company_vault: $2M in assets

// Time-based succession policy
registry.setupSimplePolicy(
    company_multisig,  // Board-controlled multisig becomes successor
    ONE_YEAR           // 1 year inactivity period
);

// CEO checks in monthly to prove activity
```

**Succession Flow:**
1. CEO inactive for 1 year (no check-ins)
2. Board multisig calls `executeSuccession()`
3. Board gains control of treasury
4. Board appoints new CEO
5. Board can transfer control to new CEO

**Benefits:**
- Simple, on-chain only
- No coordinator needed

**Trade-offs:**
- 1-year wait period (may be too long for startup)
- No guardian oversight during transfer

---

### Use Case 5: Governance Token Vesting with Succession

**Scenario:**
DAO issues 100K governance tokens to founder Alice:
- 4-year vesting schedule
- Tokens unlock gradually
- Need succession plan for unvested tokens

**Solution:**
```solidity
// Vesting Vault (Implements INFTLinked)
contract VestingVault is INFTLinked {
    uint256 public totalTokens = 100_000;
    uint256 public startTime;
    uint256 public vestingDuration = 4 * 365 days;
    
    function releasableAmount() public view returns (uint256) {
        uint256 elapsed = block.timestamp - startTime;
        if (elapsed >= vestingDuration) return totalTokens;
        return (totalTokens * elapsed) / vestingDuration;
    }
    
    function release() external onlyController {
        uint256 amount = releasableAmount();
        govToken.transfer(getCurrentNFTController(), amount);
    }
}

// Succession Setup
registry.setupSimplePolicy(alice_heir, ONE_YEAR);
```

**Succession Flow:**
1. Alice releases vested tokens monthly
2. After 2 years, Alice has released 50K tokens
3. Alice becomes inactive
4. 1 year passes with no check-ins
5. Alice's heir inherits Controller NFT via executeSuccession()
6. Heir continues to release remaining 50K tokens over remaining 2 years
7. Vesting schedule is respected

**Benefits:**
- Vesting continues even if founder leaves
- DAO doesn't lose allocated tokens
- Heir respects original vesting terms
- Smooth transition without disruption

**Key Insight:** The VestingVault implements INFTLinked, so it automatically recognizes the heir as controller when the NFT transfers. No state changes needed in the vault contract.

---

### Use Case 6: E-Commerce Crypto Payments

**Scenario:**
OnlineStore accepts crypto payments:
- 50,000 USDC monthly revenue
- Owner (Alice) controls wallet
- 5 employees depend on business

**Problem:**
- If Alice unavailable, cannot access funds
- Cannot pay suppliers
- Cannot pay employees
- Business grinds to halt

**Solution: Time-Based (Reference Implementation):**
```solidity
// Use time-based with partner as successor
registry.setupSimplePolicy(business_partner, SIX_MONTHS);
// Simpler, longer wait period

// Business Emergency Account Setup (onlyController can terminate/check-in)
payment_vault; // Business revenue vault with pull-payment pattern for emergencies (timelocked: 30 days no check-in)
lin_vesting_vault; // Linear vesting vault. Pulls from payment_vault for employees
cliff_vesting_vault; // Cliff vesting vault. Pulls from payment_vault for suppliers
// After wait period, onlyController check-in to payment_vault resets timelock
// Vesting vaults can be terminated by onlyController
```

---

## Advanced Use Cases

### Use Case 7: Trust Fund for Minor Child

**Scenario:**
Alice wants to set up a trust for daughter (5 years old):
- 100 ETH in assets
- Release when daughter turns 18
- If Alice dies, trust continues and relies on trustees for compliance

**Solution:**
```solidity
// Time-Locked Trust Vault (Implements INFTLinked)
contract MinorTrustVault is INFTLinked {
    address public beneficiary;        // Daughter's address
    uint256 public releaseDate;        // Daughter's 18th birthday
    
    function canWithdraw() public view returns (bool) {
        return block.timestamp >= releaseDate;
    }
    
    function withdraw() external {
        require(msg.sender == beneficiary);
        require(canWithdraw());
        // Transfer assets to beneficiary
    }

    // Trustees can perform operations with onlyController access control
    function payEstateTaxes() external onlyController {
        // Transfer taxes to tax authority
        // Incentive fee for trustee
    }
}

// Alice's Succession Setup
alice_registry.setupSimplePolicy(
    trustee_multisig,  // Legal trustees as successors
    ONE_YEAR
);

// If Alice becomes unavailable:
// 1. Trustees inherit Controller NFT after 1 year
// 2. Trustees control trust but cannot withdraw (time-locked to release date)
// 3. On daughter's 18th birthday, daughter can withdraw directly
// 4. Trustees transfer NFT to daughter when she's ready
```

**Benefits:**
- Trust continues if Alice dies
- Assets locked until maturity date
- Trustees have oversight but not premature access
- Daughter receives full amount at 18

**Key Insight:** The trust vault implements INFTLinked with dual access control: (1) onlyController for management, (2) time-lock for withdrawal. Trustees get management rights via succession, but daughter gets withdrawal rights at maturity.

---

### Use Case 8: DAO Treasury Succession

**Scenario:**
DAO has a $10M treasury:
- Founder (Alice) has operational control
- Community holds governance tokens
- Need to prevent founder-key lockup

**Problem:**
- Founder controls treasury for efficiency
- If founder disappears, treasury is locked
- Community cannot access funds
- DAO becomes paralyzed

**Solution (Alternative Implementation):**

**Note:** This describes a guardian-approved policy (not in reference). The reference uses time-based policies. Guardian approval is a valid alternative following ISuccessionRegistry.
```solidity
// DAO Setup
founder_nft.mint(); // Founder mints NFT
dao_vault: $10M treasury

// Succession Policy (Guardian-Approved - Alternative Implementation)
registry.setupGuardianPolicy(
    successor: dao_multisig,                 // Community multisig (5-of-9)
    waitPeriod: 30 days,                     // 30-day wait period
    guardians: [core_dev1, core_dev2, advisor1, advisor2],
    threshold: 2                             // Requires 2-of-4 approvals
);

// Founder checks in weekly
```

**Succession Flow:**
1. Founder inactive for 30 days (no check-ins)
2. Core team notices and discusses
3. 2-of-4 guardians approve succession
4. DAO multisig gains control
5. Community votes on new operational lead
6. Transfer NFT to new lead

**Benefits:**
- Founder maintains operational efficiency
- DAO protected from founder risk
- Short wait period (30 days) for quick recovery
- Guardian oversight prevents malicious transfers
- Community maintains ultimate control

**Implementation Note:** The minimal interface enables diverse policy types. While the reference uses time-based policies, guardian-approved, oracle-triggered, and DAO-voted policies are equally valid implementations of ISuccessionRegistry.

---

## Summary

Succession-Controlled Accounts enable diverse succession scenarios:

**Personal Use Cases:** Family inheritance, multi-generational wealth transfer (with unclaimed succession considerations), split estates between multiple beneficiaries

**Organizational Use Cases:** Company treasury continuity, DAO governance succession, startup resilience

**Business Use Cases:** E-commerce payment continuity and governance token vesting

**Advanced Patterns:** Trust funds for minors (time-locked dual access control) and guardian-approved policies (demonstrated in DAO example)

All while maintaining self-custody, trustless execution, automatic succession via INFTLinked pattern, and composability.

**Implementation Status:**
- **Reference implementation (Time-based policies):** Use Cases 1-7 are ready for testnet experimentation
- **Alternative implementations (Guardian-approved policies):** Use Case 8 (shown conceptually) requires custom development

---

**Want to implement these use cases?**
- See [IntegrationGuide.md](./IntegrationGuide.md)
- Check [Reference Implementation](../contracts/reference/)
- Review [SecurityConsiderations.md](./SecurityConsiderations.md)

---

**Last Updated:** November 2025