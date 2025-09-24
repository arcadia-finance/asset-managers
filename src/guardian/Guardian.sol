/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Owned } from "../../lib/accounts-v2/lib/solmate/src/auth/Owned.sol";

/**
 * @title Guardian
 * @author Pragma Labs
 * @notice Pause guardian for an Asset Manager.
 */
abstract contract Guardian is Owned {
    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Flag indicating if the Asset Manager is paused.
    bool public paused;

    // Address of the Guardian.
    address public guardian;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error Paused();
    error OnlyGuardian();

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event GuardianChanged(address indexed user, address indexed newGuardian);
    event PauseFlagsUpdated(bool pauseUpdate);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @dev Only guardians can call functions with this modifier.
     */
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    /**
     * @dev Throws if the Asset Manager is paused.
     */
    modifier whenNotPaused() {
        if (paused) revert Paused();
        _;
    }

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     */
    constructor(address owner_) Owned(owner_) { }

    /* //////////////////////////////////////////////////////////////
                            GUARDIAN LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets a new guardian.
     * @param guardian_ The address of the new guardian.
     */
    function changeGuardian(address guardian_) external onlyOwner {
        emit GuardianChanged(msg.sender, guardian = guardian_);
    }

    /* //////////////////////////////////////////////////////////////
                            PAUSING LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Pauses the Asset Manager.
     */
    function pause() external onlyGuardian whenNotPaused {
        emit PauseFlagsUpdated(paused = true);
    }

    /**
     * @notice Sets the pause flag of the Asset Manager.
     * @param paused_ Flag indicating if the Asset Manager is paused.
     */
    function setPauseFlag(bool paused_) external onlyOwner {
        emit PauseFlagsUpdated(paused = paused_);
    }
}
