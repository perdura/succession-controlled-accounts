// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title IRegistryFactory
 * @notice Factory for deploying succession registries with atomic authorization
 * @dev Uses EIP-1167 clones. Enforces one registry per user
 * @author Tian (@tian0)
 */
interface IRegistryFactory {
    // ============ Events ============

    /// @notice Emitted when registry is created
    event RegistryCreated(address indexed user, address indexed registry);

    /// @notice Emitted when pause state changes
    event PausedSet(bool paused);

    // ============ Core Function ============

    /// @notice Deploy succession registry for caller
    /// @dev Requires caller to have minted Controller NFT
    /// @dev Auto-authorizes registry for transfers in one transaction
    /// @return registry Deployed registry address
    function createRegistry() external returns (address registry);

    // ============ Admin Functions ============

    /// @notice Pause registry creation
    /// @param paused True to pause, false to unpause
    function setPaused(bool paused) external;

    // ============ View Functions ============

    /// @notice Get user's registry address
    /// @dev Returns address(0) if none
    /// @param user Address to query
    /// @return registry Registry address or address(0)
    function userRegistry(address user) external view returns (address registry);

    /// @notice Check if factory is paused
    /// @return isPaused Whether factory is paused
    function paused() external view returns (bool isPaused);

    /// @notice Get total number of deployed registries
    /// @return count Number of registries
    function getRegistryCount() external view returns (uint256 count);

    /// @notice Get paginated list of all registries
    /// @param start Starting index
    /// @param count Number of registries to return
    /// @return registries Array of registry addresses
    function getRegistriesPaginated(uint256 start, uint256 count) external view returns (address[] memory registries);

    /// @notice Get Controller NFT contract address
    /// @return nft Address of ControllerNFT contract
    function getControllerNFT() external view returns (address nft);

    /// @notice Get registry implementation address being cloned
    /// @return implementation Address of registry implementation contract
    function getImplementation() external view returns (address implementation);
}
