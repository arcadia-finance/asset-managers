/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_isPoolBalanced" of contract "Rebalancer".
 */
contract IsPoolBalanced_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPoolBalanced_False_LowerBound(
        PositionState memory position,
        Rebalancer.Cache memory cache
    ) public view {
        // Given: sqrtPrice <= lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, position.sqrtPrice, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolBalanced.
        // Then: It should return "false".
        assertFalse(rebalancer.isPoolBalanced(position.sqrtPrice, cache));
    }

    function testFuzz_Success_isPoolBalanced_False_UpperBound(
        PositionState memory position,
        Rebalancer.Cache memory cache
    ) public view {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice >= upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, cache.lowerBoundSqrtPrice + 1, position.sqrtPrice);

        // When: Calling isPoolBalanced.
        // Then: It should return "false".
        assertFalse(rebalancer.isPoolBalanced(position.sqrtPrice, cache));
    }

    function testFuzz_Success_isPoolBalanced_True(PositionState memory position, Rebalancer.Cache memory cache)
        public
        view
    {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice < upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, position.sqrtPrice + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolBalanced.
        // Then: It should return "true".
        assertTrue(rebalancer.isPoolBalanced(position.sqrtPrice, cache));
    }
}
