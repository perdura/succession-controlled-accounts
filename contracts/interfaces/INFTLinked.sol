// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title INFTLinked
 * @notice Base interface for contracts controlled by a Controller NFT
 * @dev When the NFT transfers, control automatically transfers to the new holder
 * @author Tian (@tian0)
 */
interface INFTLinked {
    // ============ Errors ============

    /// @notice Thrown when caller is not the current controller
    error NotNFTController();

    // ============ Events ============

    /// @notice Emitted when contract is linked to a Controller NFT
    /// @param controllerNFT The Controller NFT contract address
    /// @param originalHolder The address that originally minted the Controller NFT
    event NFTLinkingInitialized(address indexed controllerNFT, address indexed originalHolder);

    // ============ View Functions ============

    /// @notice Get the current controller of this contract
    /// @dev Must call IControllerNFT(controllerNFT).getCurrentController(originalHolder)
    /// @return controller Current address with control authority, or address(0) if NFT burned
    function getCurrentNFTController() external view returns (address controller);

    /// @notice Get the Controller NFT contract that verifies authority
    /// @return nft Controller NFT contract address
    function getControllerNFT() external view returns (address nft);

    /// @notice Get the original holder linked to the contract this interface extends to
    /// @return holder Address that originally minted the Controller NFT
    function getOriginalHolder() external view returns (address holder);

    /// @notice Check if succession has occurred
    /// @dev Returns true when current controller differs from original holder
    /// @return True if NFT has transferred to a new controller
    function hasSuccessionOccurred() external view returns (bool);
}
