// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Tian
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/ISuccessionRegistry.sol";
import "./ControllerNFT.sol";

/**
 * @title SimpleSuccessionRegistry
 * @notice Reference implementation of time-based succession with Storage Limits strategy
 * @dev Time-based inactivity policies (6 months or 1 year). Partial transfers supported when storage full
 * @author Tian (@tian0)
 */
contract SimpleSuccessionRegistry is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    ISuccessionRegistry
{
    // ============ Errors ============

    /// @notice Thrown when wait period hasn't elapsed since last check-in
    error ConditionsNotMet();

    /// @notice Thrown when caller is not the beneficiary/successor
    error Unauthorized();

    /// @notice Thrown when owner has no Controller NFTs to transfer
    error NoNFTsToTransfer();

    /// @notice Thrown when registry clone not deployed by factory
    error NotFactory();

    /// @notice Thrown when policy not configured
    error NotConfigured();

    /// @notice Thrown when policy already configured
    error AlreadyConfigured();

    /// @notice Thrown when check-in attempted too soon
    error CheckInTooSoon();

    /// @notice Thrown when zero address provided
    error ZeroAddress();

    /// @notice Thrown when beneficiary/successor lacks storage space for incoming NFTs
    /// @dev Beneficiary/Successor should burn unwanted tokens and retry
    error InsufficientSpace(uint256 currentCount, uint256 incomingCount, uint256 availableSlots);

    // ============ Constants ============

    uint256 private constant SIX_MONTHS = 180 days;
    uint256 private constant ONE_YEAR = 365 days;
    uint256 private constant MIN_CHECK_IN_INTERVAL = 7 days;

    // ============ Enums ============

    /// @notice Wait period options
    enum SimpleWaitPeriod {
        SIX_MONTHS,
        ONE_YEAR
    }

    // ============ Structs ============

    /// @notice Succession policy configuration
    struct Policy {
        address beneficiary;
        SimpleWaitPeriod waitPeriod;
        uint64 lastCheckIn;
        bool configured;
    }

    // ============ Storage ============

    /// @notice Controller NFT this registry manages
    ControllerNFT public controllerNFT;

    /// @notice Succession policy configuration storage
    Policy public policy;

    // ============ Events ============

    /// @notice Emitted when succession policy is configured
    event PolicyConfigured(address indexed beneficiary, SimpleWaitPeriod waitPeriod);

    /// @notice Emitted when beneficiary/successor is updated
    event BeneficiaryUpdated(address indexed oldBeneficiary, address indexed newBeneficiary);

    /// @notice Emitted when owner checks in
    event CheckedIn(uint64 timestamp);

    /// @notice Emitted when partial transfer occurs due to storage constraints
    /// @dev Beneficiary/Successor should burn unwanted NFTs to make space, then retry
    event PartialTransferWarning(
        address indexed owner, address indexed beneficiary, uint256 transferred, uint256 skipped
    );

    // ============ Constructor ============

    /// @notice Disable initializers for implementation contract
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /// @notice Initialize registry clone
    /// @dev Only callable by factory during deployment
    /// @param _owner Registry owner (Controller NFT holder)
    /// @param _controllerNFT Controller NFT contract address
    /// @param _factory Factory that deployed this registry
    function initialize(address _owner, address _controllerNFT, address _factory) external initializer {
        if (_owner == address(0) || _controllerNFT == address(0)) revert ZeroAddress();
        if (msg.sender != _factory) revert NotFactory();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        controllerNFT = ControllerNFT(_controllerNFT);
    }

    // ============ Configuration ============

    /// @notice Configure succession succession policy
    /// @dev Can only be called once by registry owner
    /// @param beneficiary Address of beneficiary/successor
    /// @param waitPeriod Inactivity period before transfer allowed
    function setupSimplePolicy(address beneficiary, SimpleWaitPeriod waitPeriod) external onlyOwner {
        if (policy.configured) revert AlreadyConfigured();
        if (beneficiary == address(0)) revert ZeroAddress();

        policy = Policy({
            beneficiary: beneficiary, waitPeriod: waitPeriod, lastCheckIn: uint64(block.timestamp), configured: true
        });

        emit PolicyConfigured(beneficiary, waitPeriod);
    }

    // ============ Management ============

    /// @notice Update beneficiary/successor address
    /// @dev Resets check-in timer as proof of owner activity
    /// @param newBeneficiary New beneficiary/successor address
    function updateBeneficiary(address newBeneficiary) external onlyOwner {
        if (!policy.configured) revert NotConfigured();
        if (newBeneficiary == address(0)) revert ZeroAddress();

        policy.lastCheckIn = uint64(block.timestamp);

        address oldBeneficiary = policy.beneficiary;
        policy.beneficiary = newBeneficiary;

        emit BeneficiaryUpdated(oldBeneficiary, newBeneficiary);
    }

    /// @notice Check in to prove activity and reset timer
    /// @dev Minimum 7-day interval between check-ins
    function checkIn() external onlyOwner {
        if (!policy.configured) revert NotConfigured();
        if (block.timestamp < policy.lastCheckIn + MIN_CHECK_IN_INTERVAL) {
            revert CheckInTooSoon();
        }

        policy.lastCheckIn = uint64(block.timestamp);
        emit CheckedIn(policy.lastCheckIn);
    }

    // ============ Core Function ============

    /// @notice Execute succession and transfer Controller NFTs to beneficiary/successor
    /// @dev Transfers original NFT first, then inherited NFTs. Partial transfers supported
    function executeSuccession() external nonReentrant {
        Policy memory _policy = policy;

        if (!_policy.configured) revert NotConfigured();
        if (msg.sender != _policy.beneficiary) revert Unauthorized();

        // Verify wait period elapsed
        uint256 waitPeriod = _getWaitPeriod();
        uint256 elapsed = block.timestamp - _policy.lastCheckIn;
        if (elapsed < waitPeriod) revert ConditionsNotMet();

        // Get owned tokens (minted and inherited)
        address owner_ = owner();
        uint256[] memory allTokens = controllerNFT.getUserOwnedTokens(owner_);
        if (allTokens.length == 0) revert NoNFTsToTransfer();

        // Prioritize original token first
        uint256 originalToken = controllerNFT.originalTokenId(owner_);
        uint256[] memory orderedTokens = new uint256[](allTokens.length);
        uint256 count = 0;

        // Add original token first
        for (uint256 i = 0; i < allTokens.length; i++) {
            if (allTokens[i] == originalToken && allTokens[i] != 0) {
                orderedTokens[count] = allTokens[i];
                count++;
                break;
            }
        }

        // Add inherited tokens
        for (uint256 i = 0; i < allTokens.length; i++) {
            if (allTokens[i] != originalToken && allTokens[i] != 0) {
                orderedTokens[count] = allTokens[i];
                count++;
            }
        }

        // Calculate available space
        uint256 beneficiaryTokenCount = controllerNFT.getUserOwnedTokens(_policy.beneficiary).length;
        uint256 maxTokens = controllerNFT.MAX_INHERITED_TOKENS();
        uint256 availableSlots = maxTokens > beneficiaryTokenCount ? maxTokens - beneficiaryTokenCount : 0;

        // Require at least 1 slot for original token
        if (availableSlots == 0) {
            revert InsufficientSpace(beneficiaryTokenCount, count, 0);
        }

        // Transfer what fits
        uint256 tokensToTransfer = count > availableSlots ? availableSlots : count;

        uint256 transferred = 0;
        for (uint256 i = 0; i < tokensToTransfer; i++) {
            IERC721(address(controllerNFT)).safeTransferFrom(owner_, _policy.beneficiary, orderedTokens[i]);
            transferred++;
        }

        uint256 skipped = count - transferred;

        emit SuccessionExecuted(owner_, _policy.beneficiary, transferred);

        if (skipped > 0) {
            emit PartialTransferWarning(owner_, _policy.beneficiary, transferred, skipped);
        }
    }

    // ============ View Functions ============

    /// @notice Get current policy
    /// @return Policy configuration details
    function getPolicy() external view returns (Policy memory) {
        return policy;
    }

    /// @notice Get beneficiary/successor address
    /// @return beneficiary Address of the beneficiary/successor
    function getBeneficiary() external view returns (address beneficiary) {
        return policy.beneficiary;
    }

    /// @notice Check if succession conditions are met
    /// @dev Only checks timing, not storage space
    /// @return True if conditions are met, false otherwise
    function canExecuteSuccession() external view returns (bool) {
        if (!policy.configured) return false;

        uint256 waitPeriod = _getWaitPeriod();
        uint256 elapsed = block.timestamp - policy.lastCheckIn;

        return elapsed >= waitPeriod;
    }

    /// @notice Get comprehensive registry status
    /// @return mode Registry mode ("Simple" or "Not Configured")
    /// @return beneficiary Address of beneficiary/successor
    /// @return daysUntilClaimable Days until succession can be executed
    /// @return isClaimable Whether succession can currently be executed
    function getStatus()
        external
        view
        returns (string memory mode, address beneficiary, uint256 daysUntilClaimable, bool isClaimable)
    {
        if (!policy.configured) {
            return ("Not Configured", address(0), 0, false);
        }

        mode = "Simple";
        beneficiary = policy.beneficiary;

        uint256 waitPeriod = _getWaitPeriod();
        uint256 timePassed = block.timestamp - policy.lastCheckIn;

        if (timePassed >= waitPeriod) {
            daysUntilClaimable = 0;
            isClaimable = true;
        } else {
            daysUntilClaimable = (waitPeriod - timePassed) / 1 days;
            isClaimable = false;
        }
    }

    // ============ Internal ============

    /// @notice Get wait period in seconds
    /// @return Wait period in seconds
    function _getWaitPeriod() internal view returns (uint256) {
        return policy.waitPeriod == SimpleWaitPeriod.SIX_MONTHS ? SIX_MONTHS : ONE_YEAR;
    }
}
