/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isPoolUnbalanced" of contract "Rebalancer".
 */
contract IsPoolUnbalanced_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPoolUnbalanced_true_lowerBound() public {
        // Given : sqrtPriceX96 < lowerBoundSqrtPriceX96
        Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = 0;
        position.lowerBoundSqrtPriceX96 = 1;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = rebalancer.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound() public {
        // Given : sqrtPriceX96 > upperBoundSqrtPriceX96
        Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.upperBoundSqrtPriceX96 = 0;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = rebalancer.isPoolUnbalanced(position);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_isPoolUnbalanced_false() public {
        // Given : sqrtPriceX96 is between lower and upper bounds.
        Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = 1;
        position.lowerBoundSqrtPriceX96 = 0;
        position.upperBoundSqrtPriceX96 = 2;

        // When : Calling isPoolUnbalanced
        bool isPoolUnbalanced = rebalancer.isPoolUnbalanced(position);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}