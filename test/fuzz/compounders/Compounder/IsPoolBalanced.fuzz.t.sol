/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../src/state/PositionState.sol";
import { Compounder } from "../../../../src/compounders/Compounder2.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_isPoolBalanced" of contract "Compounder".
 */
contract IsPoolBalanced_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isPoolBalanced_False_LowerBound(
        PositionState memory position,
        Compounder.Cache memory cache
    ) public {
        // Given: sqrtPrice <= lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, position.sqrtPrice, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolBalanced.
        // Then: It should return "false".
        assertFalse(compounder.isPoolBalanced(position.sqrtPrice, cache));
    }

    function testFuzz_Success_isPoolBalanced_False_UpperBound(
        PositionState memory position,
        Compounder.Cache memory cache
    ) public {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice >= upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, cache.lowerBoundSqrtPrice + 1, position.sqrtPrice);

        // When: Calling isPoolBalanced.
        // Then: It should return "false".
        assertFalse(compounder.isPoolBalanced(position.sqrtPrice, cache));
    }

    function testFuzz_Success_isPoolBalanced_True(PositionState memory position, Compounder.Cache memory cache)
        public
    {
        // Given: sqrtPrice > lowerBoundSqrtPrice.
        position.sqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE + 1, TickMath.MAX_SQRT_PRICE - 1);
        cache.lowerBoundSqrtPrice = bound(cache.lowerBoundSqrtPrice, TickMath.MIN_SQRT_PRICE, position.sqrtPrice - 1);

        // And: sqrtPrice < upperBoundSqrtPrice.
        cache.upperBoundSqrtPrice = bound(cache.upperBoundSqrtPrice, position.sqrtPrice + 1, TickMath.MAX_SQRT_PRICE);

        // When: Calling isPoolBalanced.
        // Then: It should return "true".
        assertTrue(compounder.isPoolBalanced(position.sqrtPrice, cache));
    }
}
