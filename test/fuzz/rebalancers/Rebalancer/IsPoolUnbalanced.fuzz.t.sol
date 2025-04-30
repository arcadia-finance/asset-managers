/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

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
    function testFuzz_Success_isPoolUnbalanced_true_lowerBound(
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) public {
        // Given: sqrtPriceX96 <= lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPriceX96 =
            bound(cache.lowerBoundSqrtPriceX96, position.sqrtPriceX96, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position, cache));
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound(
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) public {
        // Given: sqrtPriceX96 > lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPriceX96 =
            bound(cache.lowerBoundSqrtPriceX96, TickMath.MIN_SQRT_PRICE, position.sqrtPriceX96 - 1);

        // And: sqrtPriceX96 >= upperBoundSqrtPriceX96.
        cache.upperBoundSqrtPriceX96 =
            bound(cache.upperBoundSqrtPriceX96, cache.lowerBoundSqrtPriceX96 + 1, position.sqrtPriceX96);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position, cache));
    }

    function testFuzz_Success_isPoolUnbalanced_false(
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) public {
        // Given: sqrtPriceX96 > lowerBoundSqrtPriceX96.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        cache.lowerBoundSqrtPriceX96 =
            bound(cache.lowerBoundSqrtPriceX96, TickMath.MIN_SQRT_PRICE, position.sqrtPriceX96 - 1);

        // And: sqrtPriceX96 < upperBoundSqrtPriceX96.
        cache.upperBoundSqrtPriceX96 =
            bound(cache.upperBoundSqrtPriceX96, position.sqrtPriceX96 + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "false".
        assertFalse(rebalancer.isPoolUnbalanced(position, cache));
    }
}
