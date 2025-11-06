// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../../deployment/IAccountFactory.sol";
import "../../interfaces/IControllerNFT.sol";
import "./SimpleAccount.sol";

/**
 * @title AccountFactory
 * @notice Reference implementation for deploying SimpleAccount vaults
 * @dev Uses EIP-1167 clones. Users can deploy multiple accounts with MAX_ACCOUNTS_PER_USER = 25
 * @author Tian (@tian0)
 */
contract AccountFactory is Ownable, ReentrancyGuard, IAccountFactory {
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

    /// @notice Thrown when user reached account limit
    error AccountLimitExceeded();

    /// @notice Thrown when page size exceeds maximum
    error InvalidPageSize();

    // ============ Constants ============

    uint256 public constant MAX_ACCOUNTS_PER_USER = 25;
    uint256 public constant MAX_PAGE_SIZE = 1000;

    // ============ State ============

    /// @notice Account implementation for cloning
    address public immutable accountImplementation;

    /// @notice Controller NFT contract
    address public immutable controllerNFT;

    /// @notice User to accounts mapping
    mapping(address => address[]) public userAccounts;

    /// @notice All deployed accounts
    address[] public allAccounts;

    /// @notice Emergency pause flag
    bool private _paused;

    // ============ Events ============

    /// @notice Emitted when factory is deployed
    event FactoryDeployed(address indexed owner, address indexed factory);

    // ============ Constructor ============

    /// @notice Deploy account factory
    /// @param _accountImplementation Account implementation address
    /// @param _controllerNFT Controller NFT address
    constructor(address _accountImplementation, address _controllerNFT) Ownable(msg.sender) {
        if (_accountImplementation == address(0)) revert ZeroAddress();
        if (_controllerNFT == address(0)) revert ZeroAddress();

        accountImplementation = _accountImplementation;
        controllerNFT = _controllerNFT;

        emit FactoryDeployed(msg.sender, address(this));
    }

    // ============ Core Function ============

    /// @inheritdoc IAccountFactory
    function createAccount() external nonReentrant returns (address account) {
        if (_paused) revert Paused();
        if (!IControllerNFT(controllerNFT).hasMinted(msg.sender)) revert NoControllerNFT();
        if (IControllerNFT(controllerNFT).getCurrentController(msg.sender) == address(0)) revert NoControllerNFT();
        if (userAccounts[msg.sender].length >= MAX_ACCOUNTS_PER_USER) revert AccountLimitExceeded();

        // Deploy clone
        account = accountImplementation.clone();
        if (account == address(0)) revert CloneDeploymentFailed();

        // Initialize
        SimpleAccount(payable(account)).initialize(msg.sender, controllerNFT, address(this));

        // Track
        userAccounts[msg.sender].push(account);
        allAccounts.push(account);

        emit AccountCreated(msg.sender, account, block.chainid);

        return account;
    }

    // ============ Admin Functions ============

    /// @inheritdoc IAccountFactory
    function setPaused(bool paused_) external onlyOwner {
        _paused = paused_;
        emit PausedSet(paused_);
    }

    // ============ View Functions ============

    /// @inheritdoc IAccountFactory
    function paused() external view returns (bool isPaused) {
        return _paused;
    }

    /// @inheritdoc IAccountFactory
    function getUserAccounts(address user) external view returns (address[] memory accounts) {
        return userAccounts[user];
    }

    /// @inheritdoc IAccountFactory
    function getUserAccountCount(address user) external view returns (uint256 count) {
        return userAccounts[user].length;
    }

    /// @inheritdoc IAccountFactory
    function getAccountCount() external view returns (uint256 count) {
        return allAccounts.length;
    }

    /// @inheritdoc IAccountFactory
    function getAccountsPaginated(uint256 start, uint256 count) external view returns (address[] memory accounts) {
        if (count > MAX_PAGE_SIZE) revert InvalidPageSize();

        uint256 total = allAccounts.length;
        if (start >= total) return new address[](0);

        uint256 end = start + count;
        if (end > total) end = total;

        uint256 resultCount = end - start;
        accounts = new address[](resultCount);

        for (uint256 i = 0; i < resultCount; i++) {
            accounts[i] = allAccounts[start + i];
        }

        return accounts;
    }

    /// @inheritdoc IAccountFactory
    function getControllerNFT() external view returns (address nft) {
        return controllerNFT;
    }

    /// @inheritdoc IAccountFactory
    function getImplementation() external view returns (address implementation) {
        return accountImplementation;
    }

    /// @inheritdoc IAccountFactory
    function getMaxAccountsPerUser() external pure returns (uint256 max) {
        return MAX_ACCOUNTS_PER_USER;
    }
}
