/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Guardian } from "../../../src/guardian/Guardian.sol";
import { Guardian_Fuzz_Test } from "./_Guardian.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "changeGuardian" of contract "Guardian".
 */
contract ChangeGuardian_Guardian_Fuzz_Test is Guardian_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Guardian_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_changeGuardian_onlyOwner(address nonOwner, address newGuardian) public {
        vm.assume(nonOwner != users.owner);

        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        guardian.changeGuardian(newGuardian);
    }

    function testFuzz_Success_changeGuardian(address newGuardian) public {
        vm.prank(users.owner);
        vm.expectEmit();
        emit Guardian.GuardianChanged(users.owner, newGuardian);
        guardian.changeGuardian(newGuardian);

        assertEq(guardian.guardian(), newGuardian);
    }
}
