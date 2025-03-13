/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniV3Slipstream } from "../../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RebalancerUniV3Slipstream_Fuzz_Test } from "./_RebalancerUniV3Slipstream.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_isPoolUnbalanced" of contract "RebalancerUniV3Slipstream".
 */
contract IsPoolUnbalanced_RebalancerUniV3Slipstream_Fuzz_Test is RebalancerUniV3Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniV3Slipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPoolUnbalanced_true_lowerBound(RebalancerUniV3Slipstream.PositionState memory position)
        public
    {
        // Given: sqrtPriceX96 <= lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        position.lowerBoundSqrtPriceX96 =
            bound(position.lowerBoundSqrtPriceX96, position.sqrtPriceX96, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position));
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound(RebalancerUniV3Slipstream.PositionState memory position)
        public
    {
        // Given: sqrtPriceX96 > lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE);
        position.lowerBoundSqrtPriceX96 =
            bound(position.lowerBoundSqrtPriceX96, TickMath.MIN_SQRT_PRICE, position.sqrtPriceX96 - 1);

        // And: sqrtPriceX96 >= upperBoundSqrtPriceX96.
        position.upperBoundSqrtPriceX96 =
            bound(position.upperBoundSqrtPriceX96, position.lowerBoundSqrtPriceX96 + 1, position.sqrtPriceX96);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position));
    }

    function testFuzz_Success_isPoolUnbalanced_false(RebalancerUniV3Slipstream.PositionState memory position) public {
        // Given: sqrtPriceX96 > lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        position.lowerBoundSqrtPriceX96 =
            bound(position.lowerBoundSqrtPriceX96, TickMath.MIN_SQRT_PRICE, position.sqrtPriceX96 - 1);

        // And: sqrtPriceX96 < upperBoundSqrtPriceX96.
        position.upperBoundSqrtPriceX96 =
            bound(position.upperBoundSqrtPriceX96, position.sqrtPriceX96 + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "false".
        assertFalse(rebalancer.isPoolUnbalanced(position));
    }
}
