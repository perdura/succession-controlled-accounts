# Succession-Controlled Accounts

A standard for NFT-controlled smart contract accounts with programmable succession policies.

**Status:** Preparing for EIP submission. Community feedback welcome.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![License: CC0](https://img.shields.io/badge/License-CC0-lightgrey.svg)](LICENSE-INTERFACES)
[![Solidity](https://img.shields.io/badge/solidity-%5E0.8.20-blue.svg)](https://soliditylang.org/)
[![Coverage](https://img.shields.io/badge/coverage-97%25-brightgreen.svg)](gas-report.txt)

**Terminology Note:** This document uses "successor" to describe the person designated to gain control after succession conditions are met. The reference implementation code uses `beneficiary` as the variable name for this address. These terms refer to the same concept.

---

## What This Is

A standard for linking smart contract accounts to Controller NFTs. When the NFT transfers (according to succession policies you define), control of all linked accounts transfers automatically. Think estate and treasury planning for digital assets.

## Why This Matters

If you die tomorrow, your family can't access your crypto. Social recovery is designed for lost keys, not planned succession. Multisigs require active coordination from multiple parties. Custodial services defeat the purpose of crypto.

This standard lets you set up automatic succession:
- Check in periodically to prove you're active
- After a configured inactivity period (6 months or 1 year), your designated successor can claim control
- All accounts implementing INFTLinked automatically recognize the new controller
- No service fees, no trusted third parties, fully on-chain

The Controller NFT uses registry-linked transfers - only authorized succession registries can transfer it, preventing theft while enabling programmatic succession.

---

## Quick Example
```solidity
// 1. Mint a Controller NFT
controllerNFT.mint();

// 2. Deploy your succession registry (factory auto-authorizes)
ISuccessionRegistry registry = registryFactory.createRegistry();

// 3. Set policy (1 year inactivity, bob as successor)
registry.setupSimplePolicy(
    bob,  // Successor address (variable named 'beneficiary' in code)
    ISuccessionRegistry.SimpleWaitPeriod.ONE_YEAR
);

// 4. Deploy controlled account (vault)
IControlledAccount vault = accountFactory.createAccount();

// 5. Use it normally
vault.sweepERC20(tokenAddress, recipient, amount);
```

The successor can claim after the inactivity period. You can check in periodically to reset the timer.

**Note:** The reference factory automatically authorizes registries during deployment for convenience. For trustless deployment, you can manually deploy and call `controllerNFT.authorizeRegistry()` instead.

---

## Documentation

**Core Standard:**
- [Draft Specification](./docs/eip-succession-controlled-accounts.md) - The actual ERC proposal
- [Standard Interfaces](./contracts/interfaces/) - Interface definitions (CC0 licensed)
- [Architecture Diagrams](./docs/Diagrams.md) - How it all fits together

**Reference Implementation:**
- [Reference Contracts](./contracts/reference/) - Example implementation (MIT licensed)
- [Integration Guide](./docs/IntegrationGuide.md) - How to integrate with existing systems
- [Security Considerations](./docs/SecurityConsiderations.md) - Threat models and mitigations

**Additional:**
- [Use Cases](./docs/UseCases.md) - Real-world applications
- [FAQ](./docs/FAQ.md) - Common questions

---

## Installation
```bash
git clone https://github.com/perdura/succession-controlled-accounts
cd succession-controlled-accounts
forge build
```

## Testing
```bash
forge test                   # Run tests
forge test -vvv              # Verbose output
forge coverage --ir-minimum  # Coverage report
```

**Reference implementation coverage:** 97.0% lines, 94.9% statements, 100% function coverage (all 70 functions tested).

See [test/](./test/) for the complete test suite (209 tests covering security scenarios, edge cases, and integrations).

---

## Architecture

The standard defines three core components:

1. **Controller NFT** - Registry-linked NFT representing succession control authority
2. **Succession Registry** - Defines and enforces succession policies
3. **Controlled Accounts** - Contracts implementing INFTLinked pattern that automatically recognize succession

**Key Insight:** Only authorized succession registries can transfer the Controller NFT (validated via `isAuthorizedRegistry` check in `_update()`). This prevents theft while enabling programmatic succession.

The reference implementation uses EIP-1167 minimal proxies for gas efficiency (about 81% savings vs direct deployment).

---

## Security

**Development Status:** This reference implementation has not been formally audited. Production deployments should undergo independent security audits.

Key protections implemented:
- Succession griefing prevention (Storage Limits strategy with MAX_INHERITED_TOKENS = 8)
- Factory trust model with dual verification (factory tracking + ownership)
- Reentrancy guards on all state-changing functions
- Check-in mechanism for proof of activity
- Originally minted token burn protection

See [Security Considerations](./docs/SecurityConsiderations.md) for complete threat analysis.

**Before production use:**
- Get a professional security audit
- Test thoroughly on testnets
- Review all security documentation

---

## Project Status

Currently seeking community feedback on [Ethereum Magicians](link-pending) before formal EIP submission.

**Completed:**
- Core specification
- Reference implementation
- Comprehensive test suite
- Documentation

**Next steps:**
- Community review period
- Address feedback
- Formal EIP submission

---

## Use Cases

**Legal Disclaimer:** This standard provides technical infrastructure only and does not constitute legal advice. Smart contract succession does not replace traditional estate planning or corporate governance requirements. Consult qualified legal professionals. See [Security Considerations](./docs/SecurityConsiderations.md#legal-and-regulatory-considerations) for detailed legal analysis.

Common applications:
- Personal crypto succession planning
- DAO treasury continuity
- Organizational treasury succession
- Trust structures (using ERC-4626 vaults)
- Time-locked succession with proof-of-life

See [Use Cases](./docs/UseCases.md) for detailed examples.

---

## Contributing

Feedback welcome on:
- Specification clarity and completeness
- Security considerations
- Implementation approaches
- Integration guide
- Use case coverage

Open an issue or submit a PR. For code contributions, make sure tests pass first.

## Security Disclosure

For responsible disclosure of security vulnerabilities, please use [GitHub Security Advisories](https://github.com/perdura/succession-controlled-accounts/security/advisories/new).

Do not open public issues for security vulnerabilities.

## License

- **Interfaces** (`contracts/interfaces/`): CC0-1.0 (public domain)
- **Reference Implementation** (`contracts/reference/`): MIT

Interface definitions are public domain to encourage implementation diversity.

## Links

- [Draft Specification](./docs/eip-succession-controlled-accounts.md)
- [GitHub](https://github.com/perdura/succession-controlled-accounts)
- [Ethereum Magicians Discussion](link-when-available)

For questions or contributions, see [GitHub Issues](https://github.com/perdura/succession-controlled-accounts/issues).

---

**Tian**, 2025