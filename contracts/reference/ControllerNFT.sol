// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IControllerNFT.sol";
import "../deployment/IRegistryFactory.sol";

/**
 * @title ControllerNFT
 * @notice Reference implementation of succession-enabled NFT with Storage Limits strategy
 * @dev Each address mints once. Standard transfers blocked. MAX_INHERITED_TOKENS = 8 prevents griefing
 * @author Tian (@tian0)
 */
contract ControllerNFT is ERC721, Ownable, IControllerNFT {
    // ============ Errors ============

    /// @notice Thrown when caller is not a trusted factory (implementation-specific)
    error NotTrustedFactory();

    /// @notice Thrown when attempting to burn originally minted token
    error CannotBurnOriginalToken();

    /// @notice Thrown when caller is not authorized
    error NotAuthorized();

    /// @notice Thrown when token to remove from userOwnedToken array not found
    error TokenNotFound();

    /// @notice Thrown when received token limit would be exceeded
    /// @param currentCount Current token count
    /// @param incomingCount Tokens being transferred
    /// @param maxAllowed Maximum allowed received tokens
    error InheritedTokenLimitExceeded(uint256 currentCount, uint256 incomingCount, uint256 maxAllowed);

    // ============ Constants ============

    /// @notice Maximum inherited NFTs to prevent DoS attacks
    /// @dev Storage Limits strategy. Other implementations may use different approaches
    uint256 public constant MAX_INHERITED_TOKENS = 8;

    // ============ State ============

    /// @notice Next token ID to be minted
    uint256 public nextTokenId = 1;

    /// @notice Total number of NFTs minted
    uint256 public totalMinted;

    /// @notice Whether an address has minted their Controller NFT
    mapping(address => bool) public _hasMinted;

    /// @notice Original token ID minted by each user
    mapping(address => uint256) public _originalTokenId;

    /// @notice All token IDs owned by each user (minted + inherited)
    mapping(address => uint256[]) public userOwnedTokens;

    /// @notice Registry authorization: user => registry => authorized
    mapping(address => mapping(address => bool)) public authorizedRegistries;

    /// @notice Trusted factory addresses that can auto-authorize registries
    /// @dev Implementation-Specific: Factory Trust pattern
    mapping(address => bool) public _isTrustedFactory;

    // ============ Events ============

    /// @notice Emitted when trusted factory status changes
    /// @param factory Factory whose trust status changed
    /// @param trusted True if factory is now trusted, false if untrusted
    event TrustedFactorySet(address indexed factory, bool trusted);

    /// @notice Emitted when a Controller NFT is burned
    /// @param owner Address of the current NFT owner
    /// @param tokenId TokenId of NFT burned
    event ControllerNFTBurned(address indexed owner, uint256 indexed tokenId);

    // ============ Constructor ============

    /// @notice Deploy Controller NFT
    constructor() ERC721("ControllerNFT", "CTRL") Ownable(msg.sender) {}

    // ============ Core Functions ============

    /// @inheritdoc IControllerNFT
    function mint() external {
        if (_hasMinted[msg.sender]) revert AlreadyMinted();

        uint256 tokenId = nextTokenId++;
        totalMinted++;

        _hasMinted[msg.sender] = true;
        _originalTokenId[msg.sender] = tokenId;

        _mint(msg.sender, tokenId);
        emit ControllerNFTMinted(msg.sender, tokenId);
    }

    /// @notice Burn an inherited Controller NFT
    /// @dev Can only burn inherited tokens, not originally minted token.
    ///      Prevents locking controlled accounts permanently
    /// @param tokenId Token ID to burn
    function burn(uint256 tokenId) external {
        if (_ownerOf(tokenId) != msg.sender) revert NotAuthorized();

        if (_originalTokenId[msg.sender] == tokenId) revert CannotBurnOriginalToken();

        _burn(tokenId);
        emit ControllerNFTBurned(msg.sender, tokenId);
    }

    // ============ Transfer Logic ============

    /// @notice Override to enforce registry-only transfers
    /// @dev Blocks normal transfers. Only authorized registries can move NFTs.
    /// @param to Recipient address
    /// @param tokenId Token ID being transferred
    /// @param auth Address attempting the transfer
    /// @return from Original owner address
    function _update(address to, uint256 tokenId, address auth) internal override returns (address from) {
        from = _ownerOf(tokenId);

        // Validate registry authorization for transfers (not mints/burns)
        if (from != address(0) && to != address(0)) {
            if (!authorizedRegistries[from][auth]) {
                revert RegistryLinkedToken();
            }

            // Check storage limit
            if (userOwnedTokens[to].length >= MAX_INHERITED_TOKENS) {
                revert InheritedTokenLimitExceeded(userOwnedTokens[to].length, 1, MAX_INHERITED_TOKENS);
            }
        }

        _updateSuccessionState(from, to, tokenId);

        from = super._update(to, tokenId, auth);

        return from;
    }

    /// @notice Block approve function
    /// @dev Reverts to prevent unauthorized transfers
    function approve(address, uint256) public pure override(ERC721, IERC721) {
        revert RegistryLinkedToken();
    }

    /// @notice Block setApprovalForAll
    /// @dev Reverts to prevent unauthorized transfers
    function setApprovalForAll(address, bool) public pure override(ERC721, IERC721) {
        revert RegistryLinkedToken();
    }

    /// @notice Custom ERC721 authorization check for registry transfers
    /// @param owner Token owner
    /// @param spender Address attempting transfer
    /// @return True if spender is authorized
    function _isAuthorized(address owner, address spender, uint256) internal view override returns (bool) {
        return authorizedRegistries[owner][spender];
    }

    // ============ Succession Tracking ============

    /// @notice Update ownership tracking during transfers
    /// @param from Previous owner (address(0) for mints)
    /// @param to New owner (address(0) for burns)
    /// @param tokenId Token being transferred
    function _updateSuccessionState(address from, address to, uint256 tokenId) internal {
        if (from == address(0) && to != address(0)) {
            // Minting
            userOwnedTokens[to].push(tokenId);
        } else if (from != address(0) && to != address(0)) {
            // Transfer
            userOwnedTokens[to].push(tokenId);
            _removeTokenFromUser(from, tokenId);
        } else if (to == address(0)) {
            // Burning
            _removeTokenFromUser(from, tokenId);
        }
    }

    /// @notice Remove token from user's owned tokens array
    /// @param user User to remove token from
    /// @param tokenId Token to remove
    function _removeTokenFromUser(address user, uint256 tokenId) internal {
        uint256[] storage tokens = userOwnedTokens[user];
        uint256 length = tokens.length;

        for (uint256 i = 0; i < length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[length - 1];
                tokens.pop();
                return;
            }
        }

        revert TokenNotFound();
    }

    // ============ Factory Trust & Registry Authorization ============

    /// @inheritdoc IControllerNFT
    /// @notice Auto-authorize registry during factory deployment
    /// @dev Reference implementation restricts to trusted factories only. Performs dual verification:
    ///      Factory must track this registry for this user, and user must own the registry
    ///      Alternative implementations MAY allow users to call this directly
    function authorizeRegistry(address user, address registry) external {
        if (!_isTrustedFactory[msg.sender]) revert NotTrustedFactory();

        // Verify factory tracks this registry for this user
        address trackedRegistry = IRegistryFactory(msg.sender).userRegistry(user);
        if (trackedRegistry != registry) revert NotAuthorized();

        // Verify user owns the registry
        address registryOwner = Ownable(registry).owner();
        if (registryOwner != user) revert NotAuthorized();

        // Authorize registry
        authorizedRegistries[user][registry] = true;
        emit RegistryAuthorized(user, registry, true);
    }

    /// @notice Set trusted factory status
    /// @param factory Address of the factory
    /// @param trusted True to trust factory, false to revoke
    function setTrustedFactory(address factory, bool trusted) external onlyOwner {
        _isTrustedFactory[factory] = trusted;
        emit TrustedFactorySet(factory, trusted);
    }

    /// @inheritdoc IControllerNFT
    function isAuthorizedRegistry(address user, address registry) external view returns (bool) {
        return authorizedRegistries[user][registry];
    }

    /// @notice Check if factory is trusted factory addresses that can auto-authorize registries
    /// @param factory Address of the factory to check
    /// @return trusted True if factory is trusted
    function isTrustedFactory(address factory) external view returns (bool) {
        return _isTrustedFactory[factory];
    }

    // ============ View Functions ============

    /// @inheritdoc IControllerNFT
    function getCurrentController(address _originalHolder) external view returns (address controller) {
        uint256 tokenId = _originalTokenId[_originalHolder];
        if (tokenId == 0) return address(0); // Not minted

        return _ownerOf(tokenId); // Returns address(0) if burned
    }

    /// @inheritdoc IControllerNFT
    function originalTokenId(address user) external view returns (uint256 tokenId) {
        return _originalTokenId[user];
    }

    /// @inheritdoc IControllerNFT
    function hasMinted(address user) external view returns (bool) {
        return _hasMinted[user];
    }

    /// @notice Get all token IDs owned by user
    /// @dev Used for succession tracking and MAX_INHERITED_TOKENS enforcement
    function getUserOwnedTokens(address user) external view returns (uint256[] memory tokenIds) {
        return userOwnedTokens[user];
    }
}
