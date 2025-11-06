// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "../interfaces/INFTLinked.sol";
import "../interfaces/IControllerNFT.sol";

/**
 * @title NFTLinked
 * @notice Abstract base contract for Controller NFT-linked accounts
 * @dev Provides onlyController modifier and implements INFTLinked interface
 * @dev Inherit this to build succession-enabled contracts
 * @author Tian (@tian0)
 */
abstract contract NFTLinked is INFTLinked {
    // ============ Errors ============

    /// @notice Thrown when zero address provided for NFT contract
    error ZeroControllerNFT();

    /// @notice Thrown when zero address provided for holder
    error ZeroOriginalHolder();

    // ============ Storage ============

    /// @notice Controller NFT contract address
    /// @dev Immutable after initialization
    IControllerNFT public controllerNFT;

    /// @notice Original NFT holder this contract is linked to
    /// @dev Immutable after initialization
    address public originalHolder;

    // ============ Modifiers ============

    /// @notice Restrict function to current NFT controller only
    /// @dev Reverts if caller is not current controller or NFT was burned
    modifier onlyController() {
        address controller = getCurrentNFTController();
        if (controller == address(0) || msg.sender != controller) {
            revert NotNFTController();
        }
        _;
    }

    // ============ Initialization ============

    /// @notice Initialize NFT linking
    /// @dev Call from child contract's initializer. Can only be called once
    /// @param _controllerNFT Controller NFT contract address
    /// @param _originalHolder Original NFT holder address
    function _initializeNFTLinking(address _controllerNFT, address _originalHolder) internal {
        if (_controllerNFT == address(0)) revert ZeroControllerNFT();
        if (_originalHolder == address(0)) revert ZeroOriginalHolder();

        controllerNFT = IControllerNFT(_controllerNFT);
        originalHolder = _originalHolder;

        emit NFTLinkingInitialized(_controllerNFT, _originalHolder);
    }

    // ============ View Functions ============

    /// @inheritdoc INFTLinked
    function getCurrentNFTController() public view returns (address controller) {
        return controllerNFT.getCurrentController(originalHolder);
    }

    /// @inheritdoc INFTLinked
    function getControllerNFT() public view returns (address nft) {
        return address(controllerNFT);
    }

    /// @inheritdoc INFTLinked
    function getOriginalHolder() public view returns (address holder) {
        return originalHolder;
    }

    /// @inheritdoc INFTLinked
    function hasSuccessionOccurred() public view returns (bool) {
        address currentController = getCurrentNFTController();
        return currentController != address(0) && currentController != originalHolder;
    }
}
