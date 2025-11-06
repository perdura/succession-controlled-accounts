// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "../../interfaces/INFTLinked.sol";

/**
 * @title IControlledAccount
 * @notice Reference vault interface demonstrating INFTLinked pattern
 * @dev Not part of the core standard - shows one approach for multi-asset custody
 * @author Tian (@tian0)
 */
interface IControlledAccount is INFTLinked {
    // ============ Events ============

    /// @notice Emitted when Native currency is received
    event NativeReceived(address indexed from, uint256 amount);

    /// @notice Emitted when Native currency is swept
    event SweptNative(address indexed to, uint256 amount);

    /// @notice Emitted when ERC20 tokens are swept
    event SweptERC20(address indexed token, address indexed to, uint256 amount);

    /// @notice Emitted when ERC721 NFT is swept
    event SweptERC721(address indexed token, address indexed to, uint256 tokenId);

    /// @notice Emitted when ERC1155 tokens are swept
    event SweptERC1155(address indexed token, address indexed to, uint256 id, uint256 amount);

    /// @notice Emitted when account is initialized
    event InitializedAccount(address indexed originalHolder, uint256 chainId);

    // ============ Asset Sweep Functions ============

    /// @notice Sweep Native currency to recipient
    /// @dev Only callable by current controller
    /// @param to Recipient address
    /// @param amount Amount to sweep (use type(uint256).max for full balance)
    function sweepNative(address to, uint256 amount) external;

    /// @notice Sweep ERC20 tokens to recipient
    /// @dev Only callable by current controller
    /// @param token ERC20 token address
    /// @param to Recipient address
    /// @param amount Amount to sweep (use type(uint256).max for full balance)
    function sweepERC20(address token, address to, uint256 amount) external;

    /// @notice Sweep ERC721 NFT to recipient
    /// @dev Only callable by current controller
    /// @param token ERC721 contract address
    /// @param to Recipient address
    /// @param tokenId Token ID to sweep
    function sweepERC721(address token, address to, uint256 tokenId) external;

    /// @notice Sweep ERC1155 tokens to recipient
    /// @dev Only callable by current controller
    /// @param token ERC1155 contract address
    /// @param to Recipient address
    /// @param id Token ID to sweep
    /// @param amount Amount to sweep
    /// @param data Additional data for transfer
    function sweepERC1155(address token, address to, uint256 id, uint256 amount, bytes calldata data) external;

    /// @notice Sweep multiple ERC1155 tokens in batch
    /// @dev Only callable by current controller
    /// @param token ERC1155 contract address
    /// @param to Recipient address
    /// @param ids Array of token IDs
    /// @param amounts Array of amounts
    /// @param data Additional data for transfer
    function sweepERC1155Batch(
        address token,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;

    // ============ Convenience Functions ============

    /// @notice Sweep all Native currency to current controller
    function sweepAllNative() external;

    /// @notice Sweep all ERC20 tokens to current controller
    /// @param token ERC20 token address
    function sweepAllERC20(address token) external;

    // ============ View Functions ============

    /// @notice Get Native currency balance
    /// @return balance Current native currency balance
    function getNativeBalance() external view returns (uint256 balance);

    /// @notice Get ERC20 token balance
    /// @param token ERC20 token address
    /// @return balance Current token balance
    function getTokenBalance(address token) external view returns (uint256 balance);

    /// @notice Get comprehensive account information
    /// @return originalOwner Original account creator
    /// @return currentController Current controller address
    /// @return hasSucceeded Whether succession occurred
    /// @return nativeBalance Current native balance
    /// @return chainId Current blockchain ID
    function getAccountInfo()
        external
        view
        returns (
            address originalOwner,
            address currentController,
            bool hasSucceeded,
            uint256 nativeBalance,
            uint256 chainId
        );
}
