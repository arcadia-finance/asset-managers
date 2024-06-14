/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamAutoCompounder } from "./_SlipstreamAutoCompounder.fuzz.t.sol";
import { SlipstreamAutoCompounder_Fuzz_Test } from "./_SlipstreamAutoCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isPoolUnbalanced" of contract "SlipstreamAutoCompounder".
 */
contract IsPoolUnbalanced_SlipstreamAutoCompounder_Fuzz_Test is SlipstreamAutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamAutoCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_success_isPoolUnbalanced_true_lowerBound() public {
        // Given : sqrtPriceX96 < lowerBoundSqrtPriceX96
        SlipstreamAutoCompounder.PositionState memory position;
        position.sqrtPriceX96 = 0;
        position.lowerBoundSqrtPriceX96 = 1;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = autoCompounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_isPoolUnbalanced_true_upperBound() public {
        // Given : sqrtPriceX96 > upperBoundSqrtPriceX96
        SlipstreamAutoCompounder.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.upperBoundSqrtPriceX96 = 0;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = autoCompounder.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_isPoolUnbalanced_false() public {
        // Given : sqrtPriceX96 is between lower and upper bounds.
        SlipstreamAutoCompounder.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.lowerBoundSqrtPriceX96 = 0;
        position.upperBoundSqrtPriceX96 = 2;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = autoCompounder.isPoolUnbalanced(position);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
