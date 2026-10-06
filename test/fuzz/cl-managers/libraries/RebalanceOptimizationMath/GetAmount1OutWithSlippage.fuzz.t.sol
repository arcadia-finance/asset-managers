/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { RebalanceOptimizationMath } from "../../../../../src/cl-managers/libraries/RebalanceOptimizationMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmount1OutWithSlippage" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmount1OutWithSlippage_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getAmount1OutWithSlippage_ZeroLiquidity(SwapParams memory params) public {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity0 at least liquidity1.
        givenValidBalances(params, true);

        // And: usableLiquidity is zero.
        params.usableLiquidity = 0;

        // When: Calling _getAmount1OutWithSlippage().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getAmount1OutWithSlippage(params);
    }

    function testFuzz_Revert_getAmount1OutWithSlippage_Overflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: The normalized amount0 exceeds MAX_NORMALIZED.
        (uint256 minAmount0, uint256 maxAmount0,,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, minAmount0, maxAmount0);

        // And: The normalized amount1 does not exceed MAX_NORMALIZED.
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, 0, maxAmount1);

        // When: Calling _getAmount1OutWithSlippage().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getAmount1OutWithSlippage(params);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_AboveRange_InsufficientBalance(SwapParams memory params)
        public
        view
    {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: amount0 is smaller than the amountIn to move the price to the upper tick.
        (uint256 amountInToBound,) = getSwapToBound(params);
        params.amount0 = bound(params.amount0, 0, amountInToBound - 1);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut is the amountOut of the pool for a swap of the full amount0.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount0));
    }

    function testFuzz_Success_getAmount1OutWithSlippage_AboveRange_ExactBalance(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: The amountOut to move the price to the upper tick does not exceed the largest normalized amount1 there.
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioUpper);
        givenAmountOutToBoundAtMost(params, maxAmount1);

        // And: amount0 equals the amountIn to move the price to the upper tick.
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount0 = amountInToBound;

        // And: The normalized amount1 at the upper tick does not exceed MAX_NORMALIZED.
        params.amount1 = bound(params.amount1, 0, maxAmount1 - amountOutToBound);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut is the amountOut of the swap to the upper tick.
        assertEq(amountOut, amountOutToBound);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_AboveRange_SufficientBalance(SwapParams memory params)
        public
        view
    {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: The amountOut to move the price to the upper tick does not exceed the largest normalized amount1 there.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioUpper);
        givenAmountOutToBoundAtMost(params, maxAmount1);

        // And: amount0 is at least the amountIn to move the price to the upper tick.
        // And: The normalized balances at the upper tick do not exceed MAX_NORMALIZED.
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount0 = bound(params.amount0, amountInToBound, amountInToBound + maxAmount0);
        params.amount1 = bound(params.amount1, 0, maxAmount1 - amountOutToBound);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut includes the amountOut of the swap to the upper tick.
        assertGe(amountOut, amountOutToBound);

        // And: The pool price after the swap is not below the lower tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint160 sqrtPriceNew, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertGe(sqrtPriceNew, getSafetyBounds(params));

        // And: The swap costs at most amount0, and leaves at least one wei of it when it moves past the upper tick.
        assertLe(amountIn, amountOut > amountOutToBound ? params.amount0 - 1 : params.amount0);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_AboveRange_DustAfterMove(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: The amountOut to move the price to the upper tick does not exceed the largest normalized amount1 there.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioUpper);
        givenAmountOutToBoundAtMost(params, maxAmount1);

        // And: amount0 exceeds the amountIn to move the price to the upper tick by at most two wei.
        // And: The normalized balances at the upper tick do not exceed MAX_NORMALIZED.
        vm.assume(maxAmount0 > 0);
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount0 = amountInToBound + bound(params.amount0, 1, FixedPointMathLib.min(2, maxAmount0));
        params.amount1 = bound(params.amount1, 0, maxAmount1 - amountOutToBound);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut includes the amountOut of the swap to the upper tick.
        assertGe(amountOut, amountOutToBound);

        // And: The swap costs at most amount0, and leaves at least one wei of it when it moves past the upper tick.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(amountIn, amountOut > amountOutToBound ? params.amount0 - 1 : params.amount0);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_AboveRange_NearOptimal(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: The amountOut to move the price to the upper tick fits a position liquidity below 2^128 and the largest normalized amount1 there.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtRatioUpper);
        {
            uint256 maxPositionAmount1 = LiquidityAmounts.getAmount1ForLiquidity(
                params.sqrtRatioLower, params.sqrtRatioUpper, type(uint128).max
            );
            if (maxPositionAmount1 < maxAmount1) maxAmount1 = maxPositionAmount1;
        }
        givenAmountOutToBoundAtMost(params, maxAmount1);

        // And: amount0 is at least the amountIn to move the price to the upper tick.
        // And: The balances at the upper tick are at most 2^60 times the pool liquidity, and amount1 fits a position liquidity below 2^128.
        {
            (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
            params.amount0 = bound(params.amount0, amountInToBound, amountInToBound + maxAmount0);
            params.amount1 = bound(params.amount1, 0, maxAmount1 - amountOutToBound);
        }

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: The liquidity after the swap plus twice the rounding tolerance and the precision tolerance is at least the liquidity of the optimum.
        (uint256 optimalLiquidity, uint160 optimalSqrtPrice) = getOptimalLiquidity(params);
        (uint256 liquidity, uint256 tolerance) = getLiquidityAndTolerance(params, amountOut);
        tolerance = 2 * tolerance + getPrecisionTolerance(params, optimalLiquidity, optimalSqrtPrice);
        assertGe(liquidity + tolerance, optimalLiquidity);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_OnUpperTick(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld on the upper tick.
        givenValidSwapParamsOnBound(params, true);

        // And: The balances are at most 2^60 times the pool liquidity and below 2^128.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, FixedPointMathLib.min(maxAmount0, type(uint128).max));
        params.amount1 = bound(params.amount1, 0, FixedPointMathLib.min(maxAmount1, type(uint128).max));

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: The pool price after the swap is not above sqrtPriceOld and not below the lower tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint160 sqrtPriceNew, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(sqrtPriceNew, params.sqrtPriceOld);
        assertGe(sqrtPriceNew, getSafetyBounds(params));

        // And: The swap leaves at least one wei of amount0 when it swaps.
        assertLe(amountIn, FixedPointMathLib.zeroFloorSub(params.amount0, 1));
    }

    function testFuzz_Success_getAmount1OutWithSlippage_OnUpperTick_NearOptimal(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld on the upper tick.
        givenValidSwapParamsOnBound(params, true);

        // And: The balances are at most 2^60 times the pool liquidity and below 2^128, and amount1 fits a position liquidity below 2^128.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        maxAmount1 = FixedPointMathLib.min(
            maxAmount1,
            LiquidityAmounts.getAmount1ForLiquidity(params.sqrtRatioLower, params.sqrtRatioUpper, type(uint128).max)
        );
        params.amount0 = bound(params.amount0, 0, FixedPointMathLib.min(maxAmount0, type(uint128).max));
        params.amount1 = bound(params.amount1, 0, FixedPointMathLib.min(maxAmount1, type(uint128).max));

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: The liquidity after the swap plus the rounding and precision tolerances is at least the liquidity of the optimum.
        (uint256 optimalLiquidity, uint160 optimalSqrtPrice) = getOptimalLiquidity(params);
        (uint256 liquidity, uint256 tolerance) = getLiquidityAndTolerance(params, amountOut);
        tolerance += getPrecisionTolerance(params, optimalLiquidity, optimalSqrtPrice);
        assertGe(liquidity + tolerance, optimalLiquidity);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_InRange(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity0 at least liquidity1.
        givenValidBalances(params, true);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: The pool price after the swap is not above sqrtPriceOld and not below the lower tick by more than ⌊Δk⌋ units of sqrtPrice.
        (uint160 sqrtPriceNew, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(sqrtPriceNew, params.sqrtPriceOld);
        assertGe(sqrtPriceNew, getSafetyBounds(params));

        // And: The swap leaves at least one wei of amount0 when it swaps.
        assertLe(amountIn, FixedPointMathLib.zeroFloorSub(params.amount0, 1));
    }

    function testFuzz_Success_getAmount1OutWithSlippage_InRange_SubUnitMove(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: amount0 moves the price by at most half a unit of sqrtPrice.
        params.amount0 = bound(
            params.amount0,
            0,
            FullMath.mulDiv(params.usableLiquidity, 1 << 95, params.sqrtPriceOld) / params.sqrtPriceOld
        );

        // And: liquidity0 is at least liquidity1.
        {
            (uint256 liquidity0,) = getLiquidities(params, params.sqrtPriceOld, params.amount0, 0);
            (, uint256 maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper, uint128(liquidity0)
            );
            params.amount1 = bound(params.amount1, 0, maxAmount1);
        }

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut is at most that of ⌊1/2 + Δk⌋ units of sqrtPrice, zero inside the precision domain.
        uint256 maxMove = ((1 << 144) + (1 << 49) + uint256(params.sqrtPriceOld)) >> 145;
        assertLe(
            amountOut,
            SqrtPriceMath.getAmount1Delta(
                uint160(params.sqrtPriceOld - maxMove), params.sqrtPriceOld, params.usableLiquidity, false
            )
        );
    }

    function testFuzz_Success_getAmount1OutWithSlippage_InRange_ZeroBalances(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: Both balances are zero.
        params.amount0 = 0;
        params.amount1 = 0;

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: amountOut is zero.
        assertEq(amountOut, 0);
    }

    function testFuzz_Success_getAmount1OutWithSlippage_InRange_NearOptimal(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidSwapParams(params, true);

        // And: The balances are at most 2^60 times the pool liquidity, with liquidity0 at least liquidity1.
        givenValidBalances(params, true);

        // And: liquidity0 exceeds liquidity1.
        (uint256 liquidity0, uint256 liquidity1) =
            getLiquidities(params, params.sqrtPriceOld, params.amount0, params.amount1);
        vm.assume(liquidity0 > liquidity1);

        // When: Calling _getAmount1OutWithSlippage().
        uint256 amountOut = getAmount1OutWithSlippage(params);

        // Then: The liquidity after the swap plus the rounding and precision tolerances is at least the liquidity of the optimum.
        (uint256 optimalLiquidity, uint160 optimalSqrtPrice) = getOptimalLiquidity(params);
        (uint256 liquidity, uint256 tolerance) = getLiquidityAndTolerance(params, amountOut);
        tolerance += getPrecisionTolerance(params, optimalLiquidity, optimalSqrtPrice);
        assertGe(liquidity + tolerance, optimalLiquidity);
    }
}
