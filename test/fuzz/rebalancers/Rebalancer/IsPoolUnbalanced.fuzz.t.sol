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
        // Given: sqrtPrice <= lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, position.sqrtPrice, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position, cache));
    }

    function testFuzz_Success_isPoolUnbalanced_true_upperBound(
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) public {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice >= upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, cache.lowerBoundSqrtPrice + 1, position.sqrtPrice);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolUnbalanced(position, cache));
    }

    function testFuzz_Success_isPoolUnbalanced_false(
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache
    ) public {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice < upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, position.sqrtPrice + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolUnbalanced.
        // Then: It should return "false".
        assertFalse(rebalancer.isPoolUnbalanced(position, cache));
    }
}
