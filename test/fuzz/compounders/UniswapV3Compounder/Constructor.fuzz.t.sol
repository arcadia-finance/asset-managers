/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3Compounder_Fuzz_Test } from "./_UniswapV3Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "UniswapV3Compounder".
 */
contract Constructor_UniswapV3Compounder_Fuzz_Test is UniswapV3Compounder_Fuzz_Test {
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
        new UniswapV3Compounder(compoundThreshold, initiatorShare, tolerance);
    }

    function testFuzz_Success_Constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        public
    {
        tolerance = bound(tolerance, 0, 1e18);

        vm.prank(users.owner);
        UniswapV3Compounder compounder_ = new UniswapV3Compounder(compoundThreshold, initiatorShare, tolerance);

        assertEq(compounder_.COMPOUND_THRESHOLD(), compoundThreshold);
        assertEq(compounder_.INITIATOR_SHARE(), initiatorShare);

        uint256 lowerDeviation = FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18);
        uint256 upperDeviation = FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18);

        assertEq(compounder_.LOWER_SQRT_PRICE_DEVIATION(), lowerDeviation);
        assertEq(compounder_.UPPER_SQRT_PRICE_DEVIATION(), upperDeviation);
    }
}
