/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../libraries/LiquidityAmounts.sol";
import { SqrtPriceMath } from "../../libraries/SqrtPriceMath.sol";

library SwapMath {
    using FixedPointMathLib for uint256;

    // The minimal relative difference between liquidity0 and liquidity1, with 18 decimals precision.
    uint256 internal constant CONVERGENCE_THRESHOLD = 1e6;

    // The maximal number of iterations to find the optimal swap parameters.
    uint256 internal constant MAX_ITERATIONS = 15;

    event Log(uint256 sqrtPriceNew, uint256 amountIn, uint256 amountOut);
    event Log2(uint160 sqrtRatioLower, uint160 sqrtRatioUpper);

    function getAmountOutWithSlippage(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (uint256) {
        emit Log2(sqrtRatioLower, sqrtRatioUpper);
        emit Log(sqrtPriceOld, amountIn, amountOut);
        uint160 sqrtPriceNew;
        bool stopCondition;
        // We iteratively solve for sqrtPrice, amountOut and amountIn, so that the maximal amount of liquidity can be added to the position.
        for (uint256 i = 0; i < MAX_ITERATIONS; i++) {
            // Find a better approximation for sqrtPrice, given the best approximations for the optimal amountIn and amountOut.
            sqrtPriceNew = _approximateSqrtPriceNew(zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn, amountOut);

            emit Log(sqrtPriceNew, amountIn, amountOut);

            // If the position is out of range, we can calculate the exact solution.
            if (sqrtPriceNew > sqrtRatioUpper) {
                // Position is out of range and fully in token1.
                // Swapping token0 to token1 decreases the sqrtPrice, hence a swap with more amount0 might bring position in range again.
                // This would not lead to a reverting swap, but slightly less optimised, so we ignore this edge case.
                return _getAmount1OutFromAmountOIn(fee, usableLiquidity, sqrtPriceOld, amount0);
            } else if (sqrtPriceNew < sqrtRatioLower) {
                // Position is out of range and fully in token0.
                // Swapping token1 to token0 increases the sqrtPrice, hence a swap with more amount1 might bring position in range again.
                // This would not lead to a reverting swap, but slightly less optimised, so we ignore this edge case.
                return _getAmount0OutFromAmount1In(fee, usableLiquidity, sqrtPriceOld, amount1);
            }

            // If the position is not out of range, calculate the amountIn and amountOut, given the new approximated sqrtPrice.
            (amountIn, amountOut) = _getSwapParamsExact(zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtPriceNew);

            emit Log(sqrtPriceNew, amountIn, amountOut);

            // Given the new approximated sqrtPriceNew and its swap amounts,
            // calculate a better approximation for the optimal amountIn and amountOut, that would maximise the liquidity provided
            // (no leftovers of either token0 or token1).
            (stopCondition, amountIn, amountOut) = _approximateOptimalSwapAmounts(
                zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPriceNew
            );

            emit Log(sqrtPriceNew, amountIn, amountOut);

            // Check if stop condition of iteration is met:
            // The relative difference between liquidity0 and liquidity1 is below the convergence threshold.
            if (stopCondition) return amountOut;
            // If not, we do an extra iteration with our better approximated amountIn and amountOut.
        }
        // If solution did not converge within MAX_ITERATIONS steps, we use the amountOut of the last iteration step.
        return amountOut;
    }

    // ToDo: Use the geometric average?
    function _approximateSqrtPriceNew(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (uint160 sqrtPriceNew) {
        // Calculate the exact sqrtPriceNew for both amountIn and amountOut.
        // Both solutions will be different, but they with converge with every iteration closer to the same solution.
        uint256 amountInLessFee = amountIn.mulDivDown(1e6 - fee, 1e6);
        uint160 sqrtPriceNew0;
        uint160 sqrtPriceNew1;
        if (zeroToOne) {
            sqrtPriceNew0 = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                sqrtPriceOld, usableLiquidity, amountInLessFee, true
            );
            sqrtPriceNew1 =
                SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(sqrtPriceOld, usableLiquidity, amountOut, false);
        } else {
            sqrtPriceNew1 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                sqrtPriceOld, usableLiquidity, amountInLessFee, true
            );
            sqrtPriceNew0 =
                SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceOld, usableLiquidity, amountOut, false);
        }
        emit Log2(sqrtPriceNew0, sqrtPriceNew1);
        // Calculate the new best approximation as the arithmetic average of both solutions.
        // We could as well use the geometric average, but empirically we found no difference in conversion rate,
        // while the geometric average is more expensive to calculate.
        sqrtPriceNew = (sqrtPriceNew0 + sqrtPriceNew1) / 2;
    }

    function _getAmount1OutFromAmountOIn(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount0)
        internal
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInLessFee = amount0.mulDivUp(1e6 - fee, 1e6);
        uint160 sqrtPriceNew =
            SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceOld, usableLiquidity, amountInLessFee, true);
        amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false);
    }

    function _getAmount0OutFromAmount1In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount1)
        internal
        pure
        returns (uint256 amountOut)
    {
        uint256 amountInLessFee = amount1.mulDivUp(1e6 - fee, 1e6);
        uint160 sqrtPriceNew =
            SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(sqrtPriceOld, usableLiquidity, amountInLessFee, true);
        amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
    }

    function _getSwapParamsExact(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtPriceNew
    ) internal pure returns (uint256 amountIn, uint256 amountOut) {
        if (zeroToOne) {
            uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, true);
            amountIn = amountInLessFee.mulDivUp(1e6, 1e6 - fee);
            amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false);
        } else {
            uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
            amountIn = amountInLessFee.mulDivUp(1e6, 1e6 - fee);
            amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, true);
        }
    }

    event Log3(uint256 liquidity0, uint256 liquidity1);

    function _approximateOptimalSwapAmounts(
        bool zeroToOne,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPrice
    ) internal returns (bool converged, uint256 amountIn_, uint256 amountOut_) {
        // Calculate the liquidity for the given sqrtPrice and swap amounts.
        uint128 liquidity;
        {
            uint128 liquidity0;
            uint128 liquidity1;
            if (zeroToOne) {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                    sqrtPrice, sqrtRatioUpper, amount0 > amountIn ? amount0 - amountIn : 0
                );
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, sqrtPrice, amount1 + amountOut);
            } else {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPrice, sqrtRatioUpper, amount0 + amountOut);
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                    sqrtRatioLower, sqrtPrice, amount1 > amountIn ? amount1 - amountIn : 0
                );
            }
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
            emit Log3(liquidity0, liquidity1);

            // Calculate the relative difference of liquidity0 and liquidity1.
            uint256 relDiff = 1e18
                - (
                    liquidity0 < liquidity1
                        ? uint256(liquidity0).mulDivDown(1e18, liquidity1)
                        : uint256(liquidity1).mulDivDown(1e18, liquidity0)
                );
            // In the optimal solution liquidity0 equals liquidity1,
            // and there are no leftovers for token0 or token1 after minting the liquidity.
            // Hence the relative distance between liquidity0 and liquidity1
            // is a good estimator how close we are to the optimal solution.
            converged = relDiff < CONVERGENCE_THRESHOLD;
        }

        // From the new liquidity, calculated from the best approximated sqrtPriceNew,
        // calculate the new approximated amountIn and amountOut,
        // for which that liquidity would bethe optimal solution.
        uint256 amount0New = SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtRatioUpper, liquidity, true);
        uint256 amount1New = SqrtPriceMath.getAmount1Delta(sqrtRatioLower, sqrtPrice, liquidity, true);
        if (zeroToOne) {
            amountIn_ = amount0 - amount0New;
            amountOut_ = amount1New > amount1 ? amount1New - amount1 : 0;
        } else {
            amountOut_ = amount0New > amount0 ? amount0New - amount0 : 0;
            amountIn_ = amount1 - amount1New;
        }
    }
}
