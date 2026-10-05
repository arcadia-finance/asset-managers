/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPrice" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetSqrtPrice_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPrice_ZeroToOne_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_ZeroToOne_Liquidity1Exceeds(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: liquidity1 exceeds liquidity0 by more than the rounding.
        givenValidBalancesBeyondMargin(params, false);

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_ZeroToOne_Liquidity0Exceeds(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: liquidity0 exceeds liquidity1 by more than the rounding.
        givenValidBalancesBeyondMargin(params, true);

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: sqrtPriceNew is not above sqrtPriceOld and not below the lower tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint256 sqrtPriceLimit,) = getSafetyBounds(params);
        assertLe(sqrtPriceNew, params.sqrtPriceOld);
        assertGe(sqrtPriceNew, sqrtPriceLimit);

        // And: The exact crossing lies within the precision window before sqrtPriceNew and one unit more beyond it.
        uint256 window = ((params.sqrtPriceOld - sqrtPriceNew) >> 95) + (params.sqrtPriceOld >> 145) + 2;
        uint160 sqrtPriceBound =
            sqrtPriceNew + window < params.sqrtPriceOld ? uint160(sqrtPriceNew + window) : params.sqrtPriceOld;
        (uint256 liquidityIn, uint256 liquidityOut) = getLiquiditiesAfterMove(params, sqrtPriceBound, true);
        assertGe(liquidityIn, liquidityOut);
        if (sqrtPriceNew > params.sqrtRatioLower + window + 1) {
            (liquidityIn, liquidityOut) = getLiquiditiesAfterMove(params, uint160(sqrtPriceNew - window - 1), false);
            assertGe(liquidityOut, liquidityIn);
        }
    }

    function testFuzz_Success_getSqrtPrice_OneToZero_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_OneToZero_Liquidity0Exceeds(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: liquidity0 exceeds liquidity1 by more than the rounding.
        givenValidBalancesBeyondMargin(params, true);

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: It returns sqrtPriceOld.
        assertEq(sqrtPriceNew, params.sqrtPriceOld);
    }

    function testFuzz_Success_getSqrtPrice_OneToZero_Liquidity1Exceeds(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: liquidity1 exceeds liquidity0 by more than the rounding.
        givenValidBalancesBeyondMargin(params, false);

        // When: Calling _getSqrtPrice().
        uint160 sqrtPriceNew = getSqrtPrice(params);

        // Then: sqrtPriceNew is not below sqrtPriceOld and not above the upper tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint256 sqrtPriceLimit,) = getSafetyBounds(params);
        assertGe(sqrtPriceNew, params.sqrtPriceOld);
        assertLe(sqrtPriceNew, sqrtPriceLimit);

        // And: The exact crossing lies within the precision window before sqrtPriceNew and one unit more beyond it.
        uint256 window = ((sqrtPriceNew - params.sqrtPriceOld) >> 95) + (params.sqrtPriceOld >> 145) + 2;
        uint160 sqrtPriceBound =
            sqrtPriceNew > params.sqrtPriceOld + window ? uint160(sqrtPriceNew - window) : params.sqrtPriceOld;
        (uint256 liquidityIn, uint256 liquidityOut) = getLiquiditiesAfterMove(params, sqrtPriceBound, true);
        assertGe(liquidityIn, liquidityOut);
        if (sqrtPriceNew + window + 1 < params.sqrtRatioUpper) {
            (liquidityIn, liquidityOut) = getLiquiditiesAfterMove(params, uint160(sqrtPriceNew + window + 1), false);
            assertGe(liquidityOut, liquidityIn);
        }
    }
}
