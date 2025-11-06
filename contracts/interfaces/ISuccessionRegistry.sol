// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title ISuccessionRegistry
 * @notice Interface for succession execution
 * @dev Transfers Controller NFTs when policy conditions are met
 * @dev Implementations choose their own policy mechanism and griefing protection strategy
 * @author Tian (@tian0)
 */
interface ISuccessionRegistry {
    // ============ Events ============

    /// @notice Emitted when succession executes successfully
    /// @param from Original controller
    /// @param to New controller
    /// @param tokenCount Number of Controller NFTs transferred
    event SuccessionExecuted(address indexed from, address indexed to, uint256 tokenCount);

    // ============ Core Function ============

    /// @notice Execute succession and transfer Controller NFTs to successor
    /// @dev Must verify conditions, be authorized in IControllerNFT, and protect against griefing
    function executeSuccession() external;
}
