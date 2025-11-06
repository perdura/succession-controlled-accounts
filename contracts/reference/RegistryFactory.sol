// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../deployment/IRegistryFactory.sol";
import "../interfaces/IControllerNFT.sol";
import "../reference/SimpleSuccessionRegistry.sol";

/**
 * @title RegistryFactory
 * @notice Reference implementation for deploying succession registries
 * @dev Uses EIP-1167 clones. Enforces one registry per user with auto-authorization
 * @author Tian (@tian0)
 */
contract RegistryFactory is Ownable, ReentrancyGuard, IRegistryFactory {
    using Clones for address;

    // ============ Errors ============

    /// @notice Thrown when zero address provided in constructor
    error ZeroAddress();

    /// @notice Thrown when user lacks valid Controller NFT
    error NoControllerNFT();

    /// @notice Thrown when implementation not deployed
    error ImplementationNotDeployed();

    /// @notice Thrown when clone deployment failed
    error CloneDeploymentFailed();

    /// @notice Thrown when factory is paused
    error Paused();

    /// @notice Thrown when user already has a registry
    error RegistryAlreadyExists();

    /// @notice Thrown when page size exceeds maximum
    error InvalidPageSize();

    // ============ Constants ============

    uint256 public constant MAX_PAGE_SIZE = 1000;

    // ============ State ============

    /// @notice Registry implementation for cloning
    address public immutable registryImplementation;

    /// @notice Controller NFT contract
    address public immutable controllerNFT;

    /// @notice User to registry mapping (one per user)
    mapping(address => address) public _userRegistry;

    /// @notice All deployed registries
    address[] public allRegistries;

    /// @notice Emergency pause flag
    bool private _paused;

    // ============ Events ============

    /// @notice Emitted when factory is deployed
    event FactoryDeployed(address indexed owner, address indexed factory);

    // ============ Constructor ============

    /// @notice Deploy registry factory
    /// @param _registryImplementation Registry implementation address
    /// @param _controllerNFT Controller NFT address
    constructor(address _registryImplementation, address _controllerNFT) Ownable(msg.sender) {
        if (_registryImplementation == address(0)) revert ZeroAddress();
        if (_controllerNFT == address(0)) revert ZeroAddress();

        registryImplementation = _registryImplementation;
        controllerNFT = _controllerNFT;

        emit FactoryDeployed(msg.sender, address(this));
    }

    // ============ Core Function ============

    /// @inheritdoc IRegistryFactory
    function createRegistry() external nonReentrant returns (address registry) {
        if (_paused) revert Paused();
        if (!IControllerNFT(controllerNFT).hasMinted(msg.sender)) revert NoControllerNFT();
        if (IControllerNFT(controllerNFT).getCurrentController(msg.sender) == address(0)) revert NoControllerNFT();
        if (_userRegistry[msg.sender] != address(0)) revert RegistryAlreadyExists();

        // Deploy clone
        registry = registryImplementation.clone();
        if (registry == address(0)) revert CloneDeploymentFailed();

        // Track
        _userRegistry[msg.sender] = registry;
        allRegistries.push(registry);

        // Initialize
        SimpleSuccessionRegistry(registry).initialize(msg.sender, controllerNFT, address(this));

        // Auto-authorize
        IControllerNFT(controllerNFT).authorizeRegistry(msg.sender, registry);

        emit RegistryCreated(msg.sender, registry);

        return registry;
    }

    // ============ Admin Functions ============

    /// @inheritdoc IRegistryFactory
    function setPaused(bool paused_) external onlyOwner {
        _paused = paused_;
        emit PausedSet(paused_);
    }

    // ============ View Functions ============

    /// @inheritdoc IRegistryFactory
    function userRegistry(address user) external view returns (address registry) {
        return _userRegistry[user];
    }

    /// @inheritdoc IRegistryFactory
    function paused() external view returns (bool isPaused) {
        return _paused;
    }

    /// @inheritdoc IRegistryFactory
    function getRegistryCount() external view returns (uint256 count) {
        return allRegistries.length;
    }

    /// @inheritdoc IRegistryFactory
    function getRegistriesPaginated(uint256 start, uint256 count) external view returns (address[] memory registries) {
        if (count > MAX_PAGE_SIZE) revert InvalidPageSize();

        uint256 total = allRegistries.length;
        if (start >= total) return new address[](0);

        uint256 end = start + count;
        if (end > total) end = total;

        uint256 resultCount = end - start;
        registries = new address[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            registries[i] = allRegistries[start + i];
        }

        return registries;
    }

    /// @inheritdoc IRegistryFactory
    function getControllerNFT() external view returns (address nft) {
        return controllerNFT;
    }

    /// @inheritdoc IRegistryFactory
    function getImplementation() external view returns (address implementation) {
        return registryImplementation;
    }
}
