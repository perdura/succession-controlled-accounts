# Architecture Diagrams - Succession-Controlled Accounts

**Terminology Note:** This document uses "successor" to describe the person designated to gain control after succession conditions are met. The reference implementation code uses `beneficiary` as the variable name for this address. These terms refer to the same concept.

---

## Table of Contents

- [System Overview](#system-overview)
- [Component Architecture](#component-architecture)
- [Succession Flows](#succession-flows)
- [Integration Patterns](#integration-patterns)
- [Security Model](#security-model)
- [Deployment Patterns](#deployment-patterns)

---

## System Overview

### High-Level Architecture

*The following diagram shows the reference implementation architecture:*
```mermaid
flowchart LR
    subgraph Deploy[" "]
        direction TB
        DTitle["SETUP"]
        D1["Mint Controller NFT<br/>one per user"]
        D2["Deploy Registry via Factory<br/>Auto-authorizes in NFT"]
        D3["Deploy Accounts via Factory<br/>Links to Controller NFT"]
        
        DTitle -.- D1
        D1 --> D2 --> D3
    end
    
    Deploy ~~~ Operations
    
    subgraph Operations[" "]
        direction TB
        OTitle["ACTIVE MANAGEMENT"]
        O1["onlyOwner:<br/>• setup policy<br/>• check-in<br/>• update beneficiary"]
        O2["onlyController:<br/>• sweep assets"]
        
        OTitle -.- REG2["Registry"]
        OTitle -.- ACC2["Accounts"]
        REG2 --> O1
        ACC2 --> O2
    end
    
    Operations ~~~ Runtime
    
    subgraph Runtime[" "]
        direction TB
        RTitle["SUCCESSION FLOW"]
        REG["Registry<br/>(verifies policy on<br/>executeSuccession)"]
        ASSETS["Digital Assets"]
        SUCC["Successor"]
        ACC["Accounts"]
        NFT["Controller NFT"]
        
        RTitle -.- REG
        RTitle -.- ASSETS
        REG -->|transfers NFT| SUCC
        ASSETS -->|held by| ACC
        SUCC -->|controls| NFT
        ACC <-->|query| NFT
    end
```

---

### Three-Layer Model

```mermaid
flowchart LR
    NFT1[Layer 1: Controller NFT<br/>Identity & Control]
    Registry1[Layer 2: Succession Registry<br/>Policy & Logic]
    Accounts1[Layer 3: Controlled Accounts<br/>Asset Custody]
    
    NFT1 -->|controls| Registry1
    Registry1 -->|determines access| Accounts1
```

---

## Component Architecture

### Controller NFT - Internal Structure
```mermaid
flowchart TD
    Title["<b>ControllerNFT.sol</b>"]
    
    SV["<b>STATE VARIABLES:</b><br/>----<br/>uint256 public nextTokenId = 1<br/>uint256 public constant MAX_INHERITED_TOKENS = 8<br/>mapping(address => bool) public hasMinted<br/>mapping(address => uint256) public originalTokenId<br/>mapping(address => uint256[]) userOwnedTokens<br/>mapping(user => mapping(registry => bool))<br/>    authorizedRegistries"]
    
    KF["<b>KEY FUNCTIONS:</b><br/>----<br/>mint() // One per user<br/>burn(tokenId) // Clear unwanted NFTs<br/>getCurrentController(originalHolder)<br/>authorizeRegistry(user, registry)<br/>getUserOwnedTokens(user)"]
    
    SB["<b>SPECIAL BEHAVIORS:</b><br/>----<br/>✗ approve() → reverts (RegistryLinkedToken)<br/>✗ setApprovalForAll() → reverts<br/>✗ transferFrom() → reverts unless authorized<br/>✓ Transfer only via authorized registry"]
    
    Title --> SV
    Title --> KF
    Title --> SB
```

---

### Succession Registry - Internal Structure
```mermaid
flowchart TD
    Title["<b>SimpleSuccessionRegistry.sol</b>"]
    
    SV["<b>STATE VARIABLES:</b><br/>----<br/>IControllerNFT public controllerNFT<br/>address public owner<br/>address public beneficiary // Successor<br/>uint256 public lastCheckIn<br/>uint256 public waitPeriod<br/>bool public isSetup<br/>bool public hasSucceeded"]
    
    KF["<b>KEY FUNCTIONS:</b><br/>----<br/>setupSimplePolicy(beneficiary, waitPeriod)<br/>checkIn() // Proof of life<br/>updateBeneficiary(newBeneficiary)<br/>executeSuccession() // Trigger transfer"]
    
    AC["<b>ACCESS CONTROL:</b><br/>----<br/>onlyOwner:<br/>  - setupSimplePolicy()<br/>  - checkIn()<br/>  - updateBeneficiary()<br/>----<br/>successor-only (msg.sender == beneficiary):<br/>  - executeSuccession()"]
    
    Title --> SV
    Title --> KF
    Title --> AC
```

**Important:** SimpleSuccessionRegistry does NOT implement INFTLinked. Registries MANAGE the NFT, they are not CONTROLLED BY it. Only contracts that should automatically recognize succession (like vaults) implement INFTLinked.

**Note on Variable Naming:** The code uses `beneficiary` as the state variable name for the successor's address. This is preserved in code diagrams while explanatory text uses "successor."

---

### NFTLinked Pattern - Implementation Hierarchy
```mermaid
flowchart LR
    Interface["<b>INTERFACE (Standard - CC0):</b><br/>----<br/>interface INFTLinked {<br/>  function getControllerNFT() external view<br/>  function getOriginalHolder() external view<br/>  function getCurrentNFTController() external<br/>  function hasSucceeded() external view<br/>}"]
    
    Base["<b>BASE CONTRACT (Reference - MIT):</b><br/>----<br/>abstract contract NFTLinked is INFTLinked {<br/>  IControllerNFT public controllerNFT;<br/>  address public originalHolder;<br/>  // Set once in _initializeNFTLinking()<br/>----<br/>  modifier onlyController() { ... }<br/>  function getCurrentNFTController() { ... }<br/>}"]
    
    Impl["<b>IMPLEMENTATION (Reference - MIT):</b><br/>----<br/>contract SimpleAccount is NFTLinked {<br/>  function sweepNative() onlyController { ... }<br/>  function sweepERC20() onlyController { ... }<br/>  function sweepERC721() onlyController { ... }<br/>}"]
    
    KeyPoints["<b>KEY POINTS:</b><br/>----<br/>• SimpleAccount extends NFTLinked (gets implementation)<br/>• NFTLinked implements INFTLinked (standard compliance)<br/>• Succession automatic (queries ControllerNFT)<br/>• SimpleSuccessionRegistry does NOT extend NFTLinked"]
    
    Interface --> Base
    Base --> Impl
    Impl --> KeyPoints
```


---

### Controlled Account - Internal Structure
```mermaid
flowchart TD
    Title["<b>SimpleAccount.sol</b>"]
    
    SV["<b>STATE VARIABLES (from NFTLinked):</b><br/>----<br/>IControllerNFT public controllerNFT<br/>address public originalHolder<br/>// initialize() via _initializeNFTLinking<br/>----<br/><b>ACCESS CONTROL (from NFTLinked):</b><br/>modifier onlyController()<br/>"]
    
    KF["<b>KEY FUNCTIONS:</b><br/>----<br/>sweepNative(to, amount) onlyController<br/>sweepERC20(token, to, amount) onlyController<br/>sweepERC721(token, to, tokenId) onlyController<br/>sweepERC1155(token, to, id, amt) onlyController<br/>----<br/>receive() external payable // Accept ETH"]
        
    SB["<b>SUCCESSION BEHAVIOR:</b><br/>----<br/>When NFT transfers:<br/>1. ControllerNFT.ownerOf() returns new owner<br/>2. getCurrentNFTController() returns new owner<br/>3. onlyController now allows new owner<br/>4. NO state changes in SimpleAccount needed"]
    
    Title --> SV
    Title --> KF
    Title --> SB
```

---

### Succession Griefing Protection - Storage Limits
```mermaid
flowchart LR
    subgraph Left[" "]
        direction TB
        Title["SUCCESSION GRIEFING PROTECTION"]
        Problem["THE PROBLEM:
        Attacker could send 10,000 Controller NFTs to Alice.
        If executeSuccession tries to transfer all,
        gas limit would be exceeded → DoS.
        Successor cannot claim estate."]
        Solution["THE SOLUTION: Storage Limits Strategy
        MAX_INHERITED_TOKENS = 8"]
        
        Title --> Problem --> Solution
    end
    
    Left ~~~ Right
    
    subgraph Right[" "]
        direction TB
        Example["EXAMPLE:
        1. Alice inherited 8 Controller NFTs
        2. Alice: setupSimplePolicy(Bob, ONE_YEAR)
        3. Time passes (1 year no check-ins)
        4. Bob calls executeSuccession():
           Transfer #1 (original token priority)
           Transfers up to MAX_INHERITED_TOKENS limit
           Emits PartialTransferWarning
        5. To claim the remaining NFTs:
           Bob burns unwanted NFTs
           Bob calls executeSuccession again"]
        Protection["BURN PROTECTION:
        ✓ Can burn inherited NFTs from Alice
        ✗ Bob CANNOT burn his original token"]
        
        Example --> Protection
    end
```

---

## Succession Flows

### Simple Mode: Time-Based Succession Flow

```mermaid
sequenceDiagram
    participant Alice
    participant NFT as Controller NFT
    participant Registry as Succession Registry
    participant Vault as Controlled Account
    participant Bob
    
    Note over Alice,Bob: Setup Phase
    Alice->>NFT: mint()
    Alice->>Registry: deploy(nftAddress)
    Alice->>Registry: configurePolicy(Bob, 1 year)
    Alice->>Vault: deploy(nftAddress)
    Alice->>Vault: deposit assets
    
    Note over Alice,Bob: Active Phase
    loop Every few months
        Alice->>Registry: checkIn()
        Note right of Registry: Resets timer
    end
    
    Note over Alice,Bob: Inactivity Detected
    Note right of Registry: 1 year passes<br/>No check-ins
    
    Note over Alice,Bob: Succession Phase
    Bob->>Registry: executeSuccession()
    Registry->>Registry: verify conditions
    Registry->>NFT: transferFrom(Alice, Bob)
    NFT->>Bob: ownership transferred
    
    Note over Alice,Bob: Claim Phase
    Bob->>Vault: getCurrentNFTController()
    Vault-->>Bob: Bob's address
    Bob->>Vault: execute(transfer assets)
    Vault->>Bob: assets transferred
```

---

### Multi-Generation Succession

**How It Works:**
- Generation 1: Alice sets up succession to Bob
- Bob inherits Alice's NFT after conditions met
- Generation 2: Bob can update the policy or create his own NFT
- Charlie can inherit from Bob using the same pattern
- Each generation maintains the succession chain

```mermaid
sequenceDiagram
    participant Alice
    participant NFT1 as Alice's NFT
    participant Bob
    participant NFT2 as Bob's NFT
    participant Carol
    
    Note over Alice,Carol: Generation 1: Alice's successor is Bob
    Alice->>NFT1: Setup succession to Bob
    Note right of NFT1: After inactivity
    NFT1->>Bob: Transfers to Bob
    
    Note over Alice,Carol: Generation 2: Bob's successor is Carol
    Bob->>NFT1: Take control
    Bob->>NFT1: Setup succession to Carol
    Bob->>NFT2: Mint new NFT for his assets
    Note right of NFT1: After Bob's inactivity
    NFT1->>Carol: Transfers Alice's assets
    NFT2->>Carol: Transfers Bob's assets
    
    Note over Carol: Carol inherits both estates
```

---

## Integration Patterns

### ERC-6551 Token Bound Account Integration

```mermaid
flowchart TB
    CNFT[Controller NFT - Alice's succession NFT]
    Registry[Succession Registry - Policy: Bob after 1 year]
    TBA1[TBA #1 - Owns BAYC #123 + 10 ETH]
    TBA2[TBA #2 - Owns CryptoPunk #456 + USDC]
    NFT1[BAYC #123]
    NFT2[CryptoPunk #456]
    
    CNFT -->|controls| TBA1
    CNFT -->|controls| TBA2
    CNFT <-->|authorized for transfers| Registry
    
    TBA1 -.->|owned by| NFT1
    TBA2 -.->|owned by| NFT2
```

**Succession Flow:**
1. Alice controls Controller NFT which controls TBAs that controls underlying NFTs
2. After 1 year inactivity, Bob executes succession
3. Controller NFT transfers to Bob
4. Bob now controls both TBAs and their underlying NFTs
5. All assets in TBAs automatically recognize Bob

---

### ERC-4626 Trust Integration

```mermaid
flowchart TB
    CNFT[Controller NFT - Trustee's succession NFT]
    Registry[Succession Registry - Backup trustee]
    Vault4626[ERC-4626 Trust Vault - $1M in yield strategies]
    Aave[Aave Deposits]
    Compound[Compound Positions]
    Yearn[Yearn Vaults]
    Ben1[Beneficiary 1 - 30%]
    Ben2[Beneficiary 2 - 30%]
    Ben3[Beneficiary 3 - 40%]
    
    CNFT -->|controls| Vault4626
    CNFT <-->|authorized for transfers| Registry
    
    Vault4626 --> Aave
    Vault4626 --> Compound
    Vault4626 --> Yearn
    
    Vault4626 -.->|distributes| Ben1
    Vault4626 -.->|distributes| Ben2
    Vault4626 -.->|distributes| Ben3
```

**Trust Scenario:**
- Trustee manages $1M trust for 3 beneficiaries
- If trustee becomes unavailable, backup trustee takes over via succession
- Trust continues operating under new controller
- Beneficiaries' shares remain intact

---

### DeFi Protocol Integration

```mermaid
flowchart LR
    CNFT[Controller NFT]
    DeFiVault[DeFi Vault - Controlled Account]
    Uniswap[Uniswap v3 LP Position]
    Aave[Aave Lending Position]
    Compound[Compound cTokens]
    
    CNFT -->|controls| DeFiVault
    DeFiVault -->|manages| Uniswap
    DeFiVault -->|manages| Aave
    DeFiVault -->|manages| Compound
```

**Key Benefits:**
- Vault holds protocol positions (LP tokens, aTokens, cTokens)
- Positions continue earning yield during lifetime
- Upon succession, new controller claims all positions
- No need to withdraw/redeposit

---

## Security Model

### Trust Boundaries
```mermaid
flowchart TD
    Title["TRUST BOUNDARIES"]
    
    L1["LAYER 1: USER TRUST<br/>Fully User-Controlled<br/>----<br/>✓ User deploys own registry<br/>✓ User configures own policy<br/>✓ User controls check-ins<br/>✓ User chooses successor<br/>✓ User holds Controller NFT in own wallet"]
    
    L2["LAYER 2: PROTOCOL TRUST<br/>Code + Governance<br/>----<br/>Protocol Code:<br/>✓ Open source & audited<br/>✓ Immutable logic no upgrades<br/>✓ Time-locks on governance actions<br/>----<br/>Governance:<br/>• Authorizes factory contracts<br/>• Sets registry implementations<br/>• Emergency pause if needed"]
    
    L3["LAYER 3: SUCCESSOR TRUST<br/>Social<br/>----<br/>User must trust successor to:<br/>✗ Not maliciously trigger early succession<br/>✗ Respect succession intentions<br/>✗ Handle assets responsibly<br/>----<br/>NOTE: This is inherent to ALL succession<br/>planning digital and traditional"]
    
    TM["TRUST MINIMIZATION<br/>----<br/>• No admin keys in user contracts<br/>• No proxy upgrades<br/>• No centralized oracles<br/>• Pure on-chain logic<br/>• Deterministic succession conditions"]
    
    Title --> L1
    Title --> L2
    Title --> L3
    Title --> TM
```

**Trust Model:**
- **Trustless**: Core NFT → Registry → Vault flow
- **Trust Required**: Factory deployers (optional path)
- **Mitigation**: Users can deploy contracts manually without factories

---

### Attack Mitigation Layers

```mermaid
flowchart TD
    A[Attack Attempt] --> B{Layer 1: NFT Transfer Restriction}
    B -->|Only authorized registries| C{Layer 2: Registry Authorization}
    C -->|Owner must authorize| D{Layer 3: Policy Validation}
    D -->|Conditions must be met| E{Layer 4: Time Lock}
    E -->|Inactivity period elapsed| F{Layer 5: Beneficiary Auth}
    F -->|Correct beneficiary| G[Succession Executes]
    
    B -->|Unauthorized caller| X[Reverts]
    C -->|Not authorized| X
    D -->|Conditions not met| X
    E -->|Too early| X
    F -->|Wrong beneficiary| X
```

**Defense in Depth:**
1. NFT restricts transfers to authorized registries only
2. Token holder must explicitly authorize each registry
3. Policy conditions must be satisfied
4. Inactivity period prevents instant succession
5. Only designated beneficiary can execute

---

## Deployment Patterns

### Factory Pattern (Recommended)

```mermaid
sequenceDiagram
    participant User
    participant RF as RegistryFactory
    participant AF as AccountFactory
    participant CNFT as Controller NFT
    participant Reg as Registry Clone
    participant Acc as Account Clone
    
    Note over User,Acc: One-time setup (~724k gas total)
    
    User->>CNFT: mint()
    Note right of CNFT: ~186k gas
    
    User->>RF: createRegistry(nftId)
    RF->>Reg: deploy ERC-1167 clone
    Note right of Reg: ~272k gas
    RF->>Reg: initialize(user)
    RF->>CNFT: authorizeRegistry(registry)
    
    User->>AF: createAccount(nftId)
    AF->>Acc: deploy ERC-1167 clone
    Note right of Acc: ~266k gas
    AF->>Acc: initialize(nftAddress)
    
    Note over User,Acc: Total (including mint):<br/>~724k gas vs ~3.0M gas without factories<br/>Savings: 76%
```

**Gas Comparison:**

| Deployment Method | Registry | Account | Total | Savings |
|-------------------|----------|---------|-------|---------|
| Full Deploy | 1.37M gas | 1.44M gas | 2.81M | - |
| Factory Clone | 272k gas | 266k gas | 538k | 81% |

---

### Multi-Chain Deployment

```mermaid
flowchart TB
    User[User: Alice]
    Successor[Successor: Bob]
    
    M_NFT[Ethereum: Controller NFT + Registry + Vault<br/>50 ETH + NFTs, 1 year policy]
    P_NFT[Polygon: Controller NFT + Registry + Vault<br/>$100k USDC, 1 year policy]
    O_NFT[Optimism: Controller NFT + Registry + Vault<br/>DeFi positions, 1 year policy]
    
    User -.-> M_NFT
    User -.-> P_NFT
    User -.-> O_NFT
    
    Successor -.->|1. Claims first| M_NFT
    Successor -.->|2. Then claims| P_NFT
    Successor -.->|3. Then claims| O_NFT
```

**Multi-Chain Benefits:**
- ✓ Independent succession per chain
- ✓ No bridge risk during lifetime
- ✓ Lower gas costs on L2s
- ✓ Diversified infrastructure risk

**Claiming Strategy:**
1. Bob claims Ethereum estate first (highest value/gas available)
2. Uses ETH to cover gas for other chains
3. Claims Polygon, Optimism, etc.
4. Optionally bridges to preferred chain

---

## Summary

These diagrams illustrate:

**System Architecture**: Three-layer model (Identity, Policy, Custody)  
**Component Internals**: How each contract is structured  
**INFTLinked Pattern**: Interface, base contract, and implementation hierarchy  
**Succession Flows**: Simple Mode (time-based) and multi-generation inheritance  
**Integration Patterns**: ERC-6551, ERC-4626 trusts, DeFi protocols  
**Security Model**: Trust boundaries, factory trust, and attack mitigations  
**Deployment**: Factory pattern and multi-chain strategies  

---

**For Implementation Details:**
- See [IntegrationGuide.md](./IntegrationGuide.md)
- Check [Reference Implementation](../contracts/reference/)
- Review [SecurityConsiderations.md](./SecurityConsiderations.md)

---

**Last Updated:** November 2025