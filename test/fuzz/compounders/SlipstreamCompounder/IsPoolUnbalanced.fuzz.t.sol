/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounder } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isPoolUnbalanced" of contract "SlipstreamCompounder".
 */
contract IsPoolUnbalanced_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPoolUnbalanced_true_lowerBound() public {
        // Given : sqrtPriceX96 < lowerBoundSqrtPriceX96
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPriceX96 = 0;
        position.lowerBoundSqrtPriceX96 = 1;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound() public {
        // Given : sqrtPriceX96 > upperBoundSqrtPriceX96
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.upperBoundSqrtPriceX96 = 0;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_false() public {
        // Given : sqrtPriceX96 is between lower and upper bounds.
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.lowerBoundSqrtPriceX96 = 0;
        position.upperBoundSqrtPriceX96 = 2;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
