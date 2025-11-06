// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title IAccountFactory
 * @notice Factory pattern for deploying succession-enabled accounts
 * @dev Uses EIP-1167 clones. Users can deploy multiple accounts with per-user limits
 * @author Tian (@tian0)
 */
interface IAccountFactory {
    // ============ Events ============

    /// @notice Emitted when account is created
    event AccountCreated(address indexed user, address indexed account, uint256 indexed chainId);

    /// @notice Emitted when pause state changes
    event PausedSet(bool paused);

    // ============ Core Function ============

    /// @notice Deploy controlled account for caller
    /// @dev Requires caller to have minted Controller NFT
    /// @return account Deployed account address
    function createAccount() external returns (address account);

    // ============ Admin Functions ============

    /// @notice Pause account creation
    /// @param paused True to pause, false to unpause
    function setPaused(bool paused) external;

    // ============ View Functions ============

    /// @notice Check if factory is paused
    /// @return isPaused Whether factory is paused
    function paused() external view returns (bool isPaused);

    /// @notice Get all accounts created by user
    /// @param user Address to query
    /// @return accounts Array of account addresses
    function getUserAccounts(address user) external view returns (address[] memory accounts);

    /// @notice Get number of accounts created by user
    /// @param user Address to query
    /// @return count Number of accounts
    function getUserAccountCount(address user) external view returns (uint256 count);

    /// @notice Get total number of deployed accounts
    /// @return count Number of accounts
    function getAccountCount() external view returns (uint256 count);

    /// @notice Get paginated list of all accounts
    /// @param start Starting index
    /// @param count Number of accounts to return
    /// @return accounts Array of account addresses
    function getAccountsPaginated(uint256 start, uint256 count) external view returns (address[] memory accounts);

    /// @notice Get Controller NFT contract address
    /// @return nft Address of ControllerNFT contract
    function getControllerNFT() external view returns (address nft);

    /// @notice Get account implementation address being cloned
    /// @return implementation Address of registry implementation contract
    function getImplementation() external view returns (address implementation);

    /// @notice Get maximum accounts per user
    /// @return max Maximum number of accounts
    function getMaxAccountsPerUser() external view returns (uint256 max);
}
