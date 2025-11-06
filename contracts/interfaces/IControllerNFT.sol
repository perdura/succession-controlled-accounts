// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IControllerNFT
 * @notice Succession-enabled ERC-721 representing control authority
 * @dev Each address mints once. Transfers restricted to authorized registries
 * @author Tian (@tian0)
 */
interface IControllerNFT is IERC721 {
    // ============ Errors ============

    /// @notice Thrown when address already minted their Controller NFT
    error AlreadyMinted();

    /// @notice Thrown when attempting transfer without registry authorization
    error RegistryLinkedToken();

    // ============ Events ============

    /// @notice Emitted when a Controller NFT is minted
    /// @param to Address that received the NFT
    /// @param tokenId Token ID that was minted
    event ControllerNFTMinted(address indexed to, uint256 indexed tokenId);

    /// @notice Emitted when registry authorization changes
    /// @param user NFT holder whose authorization changed
    /// @param registry Registry that was authorized or deauthorized
    /// @param authorized True if authorized, false if deauthorized
    event RegistryAuthorized(address indexed user, address indexed registry, bool authorized);

    // ============ Core Functions ============

    /// @notice Mint a Controller NFT
    /// @dev Each address can mint exactly once.
    ///      Reverts if already minted
    function mint() external;

    // ============ Registry Authorization ============

    /// @notice Authorizes a registry for NFT succession transfers
    /// @param user NFT holder who owns the registry
    /// @param registry Registry contract to authorize
    function authorizeRegistry(address user, address registry) external;

    /// @notice Check if registry is authorized to transfer user's NFT
    /// @param user Address of the NFT holder
    /// @param registry Address of the registry to check
    /// @return authorized True if registry is authorized
    function isAuthorizedRegistry(address user, address registry) external view returns (bool authorized);

    // ============ View Functions ============

    /// @notice Get current controller
    /// @dev Returns current owner of the token originally minted by originalHolder
    ///      Returns address(0) if never minted or token burned
    /// @param originalHolder Address that originally minted the NFT
    /// @return controller Current controller address
    function getCurrentController(address originalHolder) external view returns (address controller);

    /// @notice Get original token ID minted by user
    /// @dev Returns 0 if user never minted
    /// @param user Address to check
    /// @return tokenId Original token ID, or 0 if never minted
    function originalTokenId(address user) external view returns (uint256 tokenId);

    /// @notice Check if address has minted their Controller NFT
    /// @param user Address to check
    /// @return minted True if user has minted
    function hasMinted(address user) external view returns (bool minted);
}
