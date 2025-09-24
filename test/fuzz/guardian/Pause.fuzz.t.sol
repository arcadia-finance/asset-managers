/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Guardian } from "../../../src/guardian/Guardian.sol";
import { Guardian_Fuzz_Test } from "./_Guardian.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "pause" of contract "Guardian".
 */
contract Pause_Guardian_Fuzz_Test is Guardian_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Guardian_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_pause_OnlyGuardian(address guardian_, address caller, bool initialFlag) public {
        // Given: Caller is not the Guardian.
        vm.assume(caller != guardian_);

        // And: Guardian is set.
        vm.prank(users.owner);
        guardian.changeGuardian(guardian_);

        // And: An initial pause flag is set.
        vm.prank(users.owner);
        guardian.setPauseFlag(initialFlag);

        // When: Caller calls pause.
        // Then: It should revert.
        vm.prank(caller);
        vm.expectRevert(Guardian.OnlyGuardian.selector);
        guardian.pause();
    }

    function testFuzz_Revert_pause_Paused(address guardian_) public {
        // Given: Guardian is set.
        vm.prank(users.owner);
        guardian.changeGuardian(guardian_);

        // And: An initial pause flag is set.
        vm.prank(users.owner);
        guardian.setPauseFlag(true);

        // When: Guardian calls pause.
        // Then: It should revert.
        vm.prank(guardian_);
        vm.expectRevert(Guardian.Paused.selector);
        guardian.pause();
    }

    function testFuzz_Success_pause(address guardian_) public {
        // Given: Guardian is set.
        vm.prank(users.owner);
        guardian.changeGuardian(guardian_);

        // When: Guardian calls pause.
        // Then: Event should be emitted.
        vm.prank(guardian_);
        vm.expectEmit();
        emit Guardian.PauseFlagsUpdated(true);
        guardian.pause();

        // Then: Contract should be paused.
        assertTrue(guardian.paused());
    }
}
