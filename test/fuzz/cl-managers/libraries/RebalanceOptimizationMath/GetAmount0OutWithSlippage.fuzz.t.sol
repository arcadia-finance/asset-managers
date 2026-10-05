/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { RebalanceOptimizationMath } from "../../../../../src/cl-managers/libraries/RebalanceOptimizationMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmount0OutWithSlippage" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmount0OutWithSlippage_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmount0OutWithSlippage_ZeroLiquidity(SwapParams memory params) public {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity1 at least liquidity0.
        givenValidBalances(params, false);

        // And: usableLiquidity is zero.
        params.usableLiquidity = 0;

        // When: Calling _getAmount0OutWithSlippage().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getAmount0OutWithSlippage(params);
    }

    function testFuzz_Revert_getAmount0OutWithSlippage_Overflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: The normalized amount1 exceeds MAX_NORMALIZED.
        (,, uint256 minAmount1, uint256 maxAmount1) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, minAmount1, maxAmount1);

        // And: The normalized amount0 does not exceed MAX_NORMALIZED.
        (uint256 maxAmount0,) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);

        // When: Calling _getAmount0OutWithSlippage().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getAmount0OutWithSlippage(params);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_BelowRange_InsufficientBalance(SwapParams memory params)
        public
        view
    {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: amount1 is smaller than the amountIn to move the price to the lower tick.
        (uint256 amountInToBound,) = getSwapToBound(params);
        params.amount1 = bound(params.amount1, 0, amountInToBound - 1);

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: amountOut is the amountOut of the pool for a swap of the full amount1.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount1));
    }

    function testFuzz_Success_getAmount0OutWithSlippage_BelowRange_ExactBalance(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: The amountOut to move the price to the lower tick does not exceed the largest normalized amount0 there.
        (uint256 maxAmount0,) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioLower);
        givenAmountOutToBoundAtMost(params, maxAmount0);

        // And: amount1 equals the amountIn to move the price to the lower tick.
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount1 = amountInToBound;

        // And: The normalized amount0 at the lower tick does not exceed MAX_NORMALIZED.
        params.amount0 = bound(params.amount0, 0, maxAmount0 - amountOutToBound);

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: amountOut is the amountOut of the swap to the lower tick.
        assertEq(amountOut, amountOutToBound);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_BelowRange_SufficientBalance(SwapParams memory params)
        public
        view
    {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: The amountOut to move the price to the lower tick does not exceed the largest normalized amount0 there.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioLower);
        givenAmountOutToBoundAtMost(params, maxAmount0);

        // And: amount1 is at least the amountIn to move the price to the lower tick.
        // And: The normalized balances at the lower tick do not exceed MAX_NORMALIZED.
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount0 = bound(params.amount0, 0, maxAmount0 - amountOutToBound);
        params.amount1 = bound(params.amount1, amountInToBound, amountInToBound + maxAmount1);

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: amountOut includes the amountOut of the swap to the lower tick.
        assertGe(amountOut, amountOutToBound);

        // And: The pool price after the swap is not above the upper tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint256 sqrtPriceLimit, uint256 maxAmountIn) = getSafetyBounds(params);
        (uint160 sqrtPriceNew, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(sqrtPriceNew, sqrtPriceLimit);

        // And: The swap costs at most ⌈κ·(1 + ν_s·Δk)⌉ wei more than amount1.
        assertLe(amountIn, maxAmountIn);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_BelowRange_NearOptimal(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: The amountOut to move the price to the lower tick fits a position liquidity below 2^128 and the largest normalized amount0 there.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioLower);
        {
            uint256 maxPositionAmount0 = LiquidityAmounts.getAmount0ForLiquidity(
                params.sqrtRatioLower, params.sqrtRatioUpper, type(uint128).max
            );
            if (maxPositionAmount0 < maxAmount0) maxAmount0 = maxPositionAmount0;
        }
        givenAmountOutToBoundAtMost(params, maxAmount0);

        // And: amount1 is at least the amountIn to move the price to the lower tick.
        // And: The balances at the lower tick are at most 2^60 times the pool liquidity, and amount0 fits a position liquidity below 2^128.
        {
            (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
            params.amount0 = bound(params.amount0, 0, maxAmount0 - amountOutToBound);
            params.amount1 = bound(params.amount1, amountInToBound, amountInToBound + maxAmount1);
        }

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: The liquidity after the swap plus twice the rounding tolerance and the precision tolerance is at least the liquidity of the optimum.
        (uint256 optimalLiquidity, uint160 optimalSqrtPrice) = getOptimalLiquidity(params);
        (uint256 liquidity, uint256 tolerance) = getLiquidityAndTolerance(params, amountOut);
        tolerance = 2 * tolerance + getPrecisionTolerance(params, optimalLiquidity, optimalSqrtPrice);
        assertGe(liquidity + tolerance, optimalLiquidity);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_InRange(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity1 at least liquidity0.
        givenValidBalances(params, false);

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: The pool price after the swap is not below sqrtPriceOld and not above the upper tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint256 sqrtPriceLimit, uint256 maxAmountIn) = getSafetyBounds(params);
        (uint160 sqrtPriceNew, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertGe(sqrtPriceNew, params.sqrtPriceOld);
        assertLe(sqrtPriceNew, sqrtPriceLimit);

        // And: The swap costs at most ⌈κ·(1 + ν_s·Δk)⌉ wei more than amount1.
        assertLe(amountIn, maxAmountIn);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_InRange_SubUnitMove(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: amount1 moves the price by at most half a unit of sqrtPrice.
        params.amount1 = bound(params.amount1, 0, params.usableLiquidity >> 97);

        // And: liquidity1 is at least liquidity0.
        {
            (, uint256 liquidity1) = getLiquidities(params, params.sqrtPriceOld, 0, params.amount1);
            (uint256 maxAmount0,) = LiquidityAmounts.getAmountsForLiquidity(
                params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper, uint128(liquidity1)
            );
            params.amount0 = bound(params.amount0, 0, maxAmount0);
        }

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: amountOut is at most that of ⌊1/2 + Δk⌋ units of sqrtPrice, zero inside the precision domain.
        uint256 maxMove = ((1 << 144) + (1 << 49) + uint256(params.sqrtPriceOld)) >> 145;
        assertLe(
            amountOut,
            SqrtPriceMath.getAmount0Delta(
                params.sqrtPriceOld, uint160(params.sqrtPriceOld + maxMove), params.usableLiquidity, false
            )
        );
    }

    function testFuzz_Success_getAmount0OutWithSlippage_InRange_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: amountOut is zero.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getAmount0OutWithSlippage_InRange_NearOptimal(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, false);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity1 at least liquidity0.
        givenValidBalances(params, false);

        // And: liquidity1 exceeds liquidity0.
        (uint256 liquidity0, uint256 liquidity1) =
            getLiquidities(params, params.sqrtPriceOld, params.amount0, params.amount1);
        vm.assume(liquidity1 > liquidity0);

        // When: Calling _getAmount0OutWithSlippage().
        uint256 amountOut = getAmount0OutWithSlippage(params);

        // Then: The liquidity after the swap plus the rounding and precision tolerances is at least the liquidity of the optimum.
        (uint256 optimalLiquidity, uint160 optimalSqrtPrice) = getOptimalLiquidity(params);
        (uint256 liquidity, uint256 tolerance) = getLiquidityAndTolerance(params, amountOut);
        tolerance += getPrecisionTolerance(params, optimalLiquidity, optimalSqrtPrice);
        assertGe(liquidity + tolerance, optimalLiquidity);
    }
}
