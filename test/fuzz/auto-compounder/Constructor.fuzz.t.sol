/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder_Fuzz_Test } from "./_AutoCompounder.fuzz.t.sol";

import { AutoCompounder } from "../../../src/auto-compounder/AutoCompounder.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "AutoCompounder".
 */
contract Constructor_AutoCompounder_Fuzz_Test is AutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_Constructor_UnderflowTolerance(
        uint256 compoundThreshold,
        uint256 initiatorShare,
        uint256 tolerance
    ) public {
        tolerance = bound(tolerance, 1e18 + 1, type(uint256).max);

        vm.prank(users.deployer);
        vm.expectRevert(stdError.arithmeticError);
        new AutoCompounder(compoundThreshold, initiatorShare, tolerance);
    }

    function testFuzz_Success_Constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        public
    {
        tolerance = bound(tolerance, 0, 1e18);

        vm.prank(users.deployer);
        AutoCompounder autoCompounder_ = new AutoCompounder(compoundThreshold, initiatorShare, tolerance);

        assertEq(autoCompounder_.COMPOUND_THRESHOLD(), compoundThreshold);
        assertEq(autoCompounder_.INITIATOR_SHARE(), initiatorShare);

        uint256 lowerDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        uint256 upperDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);

        assertEq(autoCompounder_.LOWER_SQRT_PRICE_DEVIATION(), lowerDeviation);
        assertEq(autoCompounder_.UPPER_SQRT_PRICE_DEVIATION(), upperDeviation);
    }
}
