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
        // Given : sqrtPrice < lowerBoundSqrtPrice
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPrice = 0;
        position.lowerBoundSqrtPrice = 1;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound() public {
        // Given : sqrtPrice > upperBoundSqrtPrice
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPrice = 1;
        position.upperBoundSqrtPrice = 0;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_false() public {
        // Given : sqrtPrice is between lower and upper bounds.
        SlipstreamCompounder.PositionState memory position;
        position.sqrtPrice = 1;
        position.lowerBoundSqrtPrice = 0;
        position.upperBoundSqrtPrice = 2;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = compounder.isPoolUnbalanced(position);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
