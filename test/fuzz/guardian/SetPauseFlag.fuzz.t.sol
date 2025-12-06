/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Guardian_Fuzz_Test } from "./_Guardian.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setPauseFlag" of contract "Guardian".
 */
contract SetPauseFlag_Guardian_Fuzz_Test is Guardian_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Guardian_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setPauseFlag_OnlyOwner(address caller, bool initialFlag, bool flag) public {
        // Given: Caller is not the Owner.
        vm.assume(caller != users.owner);

        // And: An initial pause flag is set.
        vm.prank(users.owner);
        guardian.setPauseFlag(initialFlag);

        // When: Caller calls setPauseFlag.
        // Then: It should revert.
        vm.prank(caller);
        vm.expectRevert("UNAUTHORIZED");
        guardian.setPauseFlag(flag);
    }

    function testFuzz_Success_setPauseFlag(bool initialFlag, bool flag) public {
        // Given: An initial pause flag is set.
        vm.prank(users.owner);
        guardian.setPauseFlag(initialFlag);

        // When: Owner calls setPauseFlag.
        // Then: Event should be emitted.
        vm.prank(users.owner);
        guardian.setPauseFlag(flag);

        // Then: Contract should be paused.
        assertEq(guardian.paused(), flag);
    }
}
