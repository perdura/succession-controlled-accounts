// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "./IControlledAccount.sol";
import "../NFTLinked.sol";

/**
 * @title SimpleAccount
 * @notice Reference vault for multi-asset custody with succession control
 * @dev Holds Native, ERC20, ERC721, and ERC1155 tokens. Control follows the Controller NFT
 * @author Tian (@tian0)
 */
contract SimpleAccount is
    Initializable,
    ReentrancyGuardUpgradeable,
    NFTLinked,
    IControlledAccount,
    IERC721Receiver,
    IERC1155Receiver
{
    using SafeERC20 for IERC20;

    // ============ Errors ============

    /// @notice Thrown when caller is not the factory
    error NotFactory();

    /// @notice Thrown when zero address provided
    error ZeroAddress();

    /// @notice Thrown when native currency transfer fails
    error NativeSendFailed();

    // ============ Initialization ============

    /// @notice Disable initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize vault clone
    /// @dev Only callable by factory during deployment
    /// @param _owner Original vault creator
    /// @param _controllerNFT Controller NFT contract address
    /// @param _factory Factory that deployed this vault
    function initialize(address _owner, address _controllerNFT, address _factory) external initializer {
        if (_owner == address(0) || _controllerNFT == address(0)) revert ZeroAddress();
        if (msg.sender != _factory) revert NotFactory();

        __ReentrancyGuard_init();
        _initializeNFTLinking(_controllerNFT, _owner);

        emit InitializedAccount(_owner, block.chainid);
    }

    // ============ Receive Functions ============

    /// @notice Accept native currency deposits
    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    // ============ Asset Sweep Functions ============

    /// @inheritdoc IControlledAccount
    function sweepNative(address to, uint256 amount) external onlyController nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        uint256 amt = amount == type(uint256).max ? address(this).balance : amount;
        if (amt > 0) {
            (bool success,) = to.call{value: amt}("");
            if (!success) revert NativeSendFailed();
            emit SweptNative(to, amt);
        }
    }

    /// @inheritdoc IControlledAccount
    function sweepERC20(address token, address to, uint256 amount) external onlyController nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();

        IERC20 t = IERC20(token);
        uint256 balance = t.balanceOf(address(this));
        uint256 amt = amount == type(uint256).max ? balance : amount;

        if (amt > 0) {
            t.safeTransfer(to, amt);
            emit SweptERC20(token, to, amt);
        }
    }

    /// @inheritdoc IControlledAccount
    function sweepERC721(address token, address to, uint256 tokenId) external onlyController nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();

        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        emit SweptERC721(token, to, tokenId);
    }

    /// @inheritdoc IControlledAccount
    function sweepERC1155(address token, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyController
        nonReentrant
    {
        if (token == address(0) || to == address(0)) revert ZeroAddress();

        IERC1155(token).safeTransferFrom(address(this), to, id, amount, data);
        emit SweptERC1155(token, to, id, amount);
    }

    /// @inheritdoc IControlledAccount
    function sweepERC1155Batch(
        address token,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyController nonReentrant {
        if (token == address(0) || to == address(0)) revert ZeroAddress();

        IERC1155(token).safeBatchTransferFrom(address(this), to, ids, amounts, data);
    }

    // ============ Convenience Functions ============

    /// @inheritdoc IControlledAccount
    function sweepAllNative() external onlyController nonReentrant {
        // msg.sender is already validated by onlyController
        uint256 balance = address(this).balance;

        if (balance > 0) {
            (bool success,) = msg.sender.call{value: balance}("");
            if (!success) revert NativeSendFailed();
            emit SweptNative(msg.sender, balance);
        }
    }

    /// @inheritdoc IControlledAccount
    function sweepAllERC20(address token) external onlyController nonReentrant {
        // msg.sender is already validated by onlyController
        if (token == address(0)) revert ZeroAddress();

        IERC20 t = IERC20(token);
        uint256 balance = t.balanceOf(address(this));

        if (balance > 0) {
            t.safeTransfer(msg.sender, balance);
            emit SweptERC20(token, msg.sender, balance);
        }
    }

    // ============ View Functions ============

    /// @inheritdoc IControlledAccount
    function getNativeBalance() external view returns (uint256 balance) {
        return address(this).balance;
    }

    /// @inheritdoc IControlledAccount
    function getTokenBalance(address token) external view returns (uint256 balance) {
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IControlledAccount
    function getAccountInfo()
        external
        view
        returns (
            address originalOwner,
            address currentController,
            bool hasSucceeded,
            uint256 nativeBalance,
            uint256 chainId
        )
    {
        originalOwner = getOriginalHolder();
        currentController = getCurrentNFTController();
        hasSucceeded = hasSuccessionOccurred();
        nativeBalance = address(this).balance;
        chainId = block.chainid;
    }

    // ============ Token Receivers ============

    /// @notice ERC721 receiver hook
    /// @param /* operator */ Address performing the transfer
    /// @param /* from */ Address transferring the token
    /// @param /* tokenId */ Token ID being transferred
    /// @param /* data */ Additional data with no specified format
    /// @return Selector confirming receipt
    function onERC721Received(
        address,
        /* operator */
        address,
        /* from */
        uint256,
        /* tokenId */
        bytes calldata /* data */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice ERC1155 receiver hook
    /// @param /* operator */ Address performing the transfer
    /// @param /* from */ Address transferring the tokens
    /// @param /* id */ Token ID being transferred
    /// @param /* value */ Amount being transferred
    /// @param /* data */ Additional data with no specified format
    /// @return Selector confirming receipt
    function onERC1155Received(
        address,
        /* operator */
        address,
        /* from */
        uint256,
        /* id */
        uint256,
        /* value */
        bytes calldata /* data */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice ERC1155 batch receiver hook
    /// @param /* operator */ Address performing the transfer
    /// @param /* from */ Address transferring the tokens
    /// @param /* ids */ Token IDs being transferred
    /// @param /* values */ Amounts being transferred
    /// @param /* data */ Additional data with no specified format
    /// @return Selector confirming receipt
    function onERC1155BatchReceived(
        address,
        /* operator */
        address,
        /* from */
        uint256[] calldata,
        /* ids */
        uint256[] calldata,
        /* values */
        bytes calldata /* data */
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @notice ERC165 support
    /// @param interfaceId Interface identifier to check
    /// @return True if interface is supported
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC165
    }
}
