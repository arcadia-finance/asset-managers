/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapV3AutoCompounder } from "../../../../src/auto-compounder/UniswapV3AutoCompounder.sol";
import { UniswapV3AutoCompounder_Fuzz_Test } from "./_UniswapV3AutoCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "UniswapV3AutoCompounder".
 */
contract Constructor_UniswapV3AutoCompounder_Fuzz_Test is UniswapV3AutoCompounder_Fuzz_Test {
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

        vm.prank(users.owner);
        vm.expectRevert(stdError.arithmeticError);
        new UniswapV3AutoCompounder(compoundThreshold, initiatorShare, tolerance);
    }

    function testFuzz_Success_Constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        public
    {
        tolerance = bound(tolerance, 0, 1e18);

        vm.prank(users.owner);
        UniswapV3AutoCompounder autoCompounder_ =
            new UniswapV3AutoCompounder(compoundThreshold, initiatorShare, tolerance);

        assertEq(autoCompounder_.COMPOUND_THRESHOLD(), compoundThreshold);
        assertEq(autoCompounder_.INITIATOR_SHARE(), initiatorShare);

        uint256 lowerDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        uint256 upperDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);

        assertEq(autoCompounder_.LOWER_SQRT_PRICE_DEVIATION(), lowerDeviation);
        assertEq(autoCompounder_.UPPER_SQRT_PRICE_DEVIATION(), upperDeviation);
    }
}
