/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../libraries/uniswap-v3/LiquidityAmounts.sol";
import { SqrtPriceMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

library RebalanceOptimizationMath {
    using FixedPointMathLib for uint256;

    // The minimal relative difference between liquidity0 and liquidity1, with 18 decimals precision.
    uint256 internal constant CONVERGENCE_THRESHOLD = 1e6;

    // The maximal number of iterations to find the optimal swap parameters.
    uint256 internal constant MAX_ITERATIONS = 100;

    /**
     * @notice Iteratively calculates the amountOut for a swap through the pool itself, that maximizes the amount of liquidity that is added.
     * The calculations take both fees and slippage into account, but assume constant liquidity.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @param amountIn An approximation of the amount of tokenIn, based on the optimal swap through the pool itself without slippage.
     * @param amountOut An approximation of the amount of tokenOut, based on the optimal swap through the pool itself without slippage.
     * @return amountOut The amount of tokenOut.
     * @dev The optimal amountIn and amountOut are defined as the amounts that maximize the amount of liquidity that can be added to the position.
     * This means that there are no leftovers of either token0 or token1,
     * and liquidity0 (calculated via getLiquidityForAmount0) will be exactly equal to liquidity1 (calculated via getLiquidityForAmount1).
     * @dev The optimal amountIn and amountOut depend on the sqrtPrice of the pool via the liquidity calculations,
     * but the sqrtPrice in turn depends on the amountIn and amountOut via the swap calculations.
     * Since both are highly non-linear, this problem is (according to our understanding) not analytically solvable.
     * Therefore we use an iterative approach to find the optimal swap parameters.
     * The stop criterium is defined when the relative difference between liquidity0 and liquidity1 is below the convergence threshold.
     * @dev Convergence is not guaranteed, worst case or the transaction reverts, or a non-optimal swap is performed,
     * But then minLiquidity enforces that either enough liquidity is minted or the transaction will revert.
     * @dev We assume constant active liquidity when calculating the swap parameters.
     * For illiquid pools, or positions that are large relatively to the pool liquidity, this might result in reverting rebalances.
     * But since a minimum amount of liquidity is enforced, should not lead to loss of principal.
     */
    function _getAmountOutWithSlippage(
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
    ) internal pure returns (uint256) {
        uint160 sqrtPriceNew;
        bool stopCondition;
        // We iteratively solve for sqrtPrice, amountOut and amountIn, so that the maximal amount of liquidity can be added to the position.
        for (uint256 i = 0; i < MAX_ITERATIONS; ++i) {
            // Find a better approximation for sqrtPrice, given the best approximations for the optimal amountIn and amountOut.
            sqrtPriceNew = _approximateSqrtPriceNew(zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn, amountOut);

            // If the position is out of range, we can calculate the exact solution.
            if (sqrtPriceNew >= sqrtRatioUpper) {
                // New position is out of range and fully in token 1.
                // Rebalance to a single-sided liquidity position in token 1.
                // We ignore one edge case: Swapping token0 to token1 decreases the sqrtPrice,
                // hence a swap for a position that is just out of range might become in range due to slippage.
                // This might lead to a suboptimal rebalance, which worst case results in too little liquidity and the rebalance reverts.
                return _getAmount1OutFromAmount0In(fee, usableLiquidity, sqrtPriceOld, amount0);
            } else if (sqrtPriceNew <= sqrtRatioLower) {
                // New position is out of range and fully in token 0.
                // Rebalance to a single-sided liquidity position in token 0.
                // We ignore one edge case: Swapping token1 to token0 increases the sqrtPrice,
                // hence a swap for a position that is just out of range might become in range due to slippage.
                // This might lead to a suboptimal rebalance, which worst case results in too little liquidity and the rebalance reverts.
                return _getAmount0OutFromAmount1In(fee, usableLiquidity, sqrtPriceOld, amount1);
            }

            // If the position is not out of range, calculate the amountIn and amountOut, given the new approximated sqrtPrice.
            (amountIn, amountOut) = _getSwapParamsExact(zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtPriceNew);

            // Given the new approximated sqrtPriceNew and its swap amounts,
            // calculate a better approximation for the optimal amountIn and amountOut, that would maximise the liquidity provided
            // (no leftovers of either token0 or token1).
            (stopCondition, amountIn, amountOut) = _approximateOptimalSwapAmounts(
                zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPriceNew
            );

            // Check if stop condition of iteration is met:
            // The relative difference between liquidity0 and liquidity1 is below the convergence threshold.
            if (stopCondition) return amountOut;
            // If not, we do an extra iteration with our better approximated amountIn and amountOut.
        }
        // If solution did not converge within MAX_ITERATIONS steps, we use the amountOut of the last iteration step.
        return amountOut;
    }

    /**
     * @notice Approximates the SqrtPrice after the swap, given an approximation for the amountIn and amountOut that maximise liquidity added.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The SqrtPrice before the swap.
     * @param amountIn An approximation of the amount of tokenIn, that maximise liquidity added.
     * @param amountOut An approximation of the amount of tokenOut, that maximise liquidity added.
     * @return sqrtPriceNew The approximation of the SqrtPrice after the swap.
     */
    function _approximateSqrtPriceNew(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint256 amountIn,
        uint256 amountOut
    ) internal pure returns (uint160 sqrtPriceNew) {
        unchecked {
            // Calculate the exact sqrtPriceNew for both amountIn and amountOut.
            // Both solutions will be different, but they will converge with every iteration closer to the same solution.
            uint256 amountInLessFee = amountIn.mulDivDown(1e6 - fee, 1e6);
            uint256 sqrtPriceNew0;
            uint256 sqrtPriceNew1;
            if (zeroToOne) {
                sqrtPriceNew0 = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                    sqrtPriceOld, usableLiquidity, amountInLessFee, true
                );
                sqrtPriceNew1 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceOld, usableLiquidity, amountOut, false
                );
            } else {
                sqrtPriceNew0 =
                    SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(sqrtPriceOld, usableLiquidity, amountOut, false);
                sqrtPriceNew1 = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                    sqrtPriceOld, usableLiquidity, amountInLessFee, true
                );
            }
            // Calculate the new best approximation as the arithmetic average of both solutions (rounded towards current price).
            // We could as well use the geometric average, but empirically we found no difference in conversion speed,
            // and the geometric average is more expensive to calculate.
            // Unchecked + unsafe cast: sqrtPriceNew0 and sqrtPriceNew1 are always smaller than type(uint160).max.
            sqrtPriceNew = zeroToOne
                ? uint160(FixedPointMathLib.unsafeDiv(sqrtPriceNew0 + sqrtPriceNew1, 2))
                : uint160(FixedPointMathLib.unsafeDivUp(sqrtPriceNew0 + sqrtPriceNew1, 2));
        }
    }

    /**
     * @notice Calculates the amountOut of token1, for a given amountIn of token0.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The SqrtPrice before the swap.
     * @param amount0 The balance of token0 before the swap.
     * @return amountOut The amount of token1 that is swapped to.
     * @dev The calculations take both fees and slippage into account, but assume constant liquidity.
     */
    function _getAmount1OutFromAmount0In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount0)
        internal
        pure
        returns (uint256 amountOut)
    {
        unchecked {
            uint256 amountInLessFee = amount0.mulDivUp(1e6 - fee, 1e6);
            uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                sqrtPriceOld, usableLiquidity, amountInLessFee, true
            );
            amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false);
        }
    }

    /**
     * @notice Calculates the amountOut of token0, for a given amountIn of token1.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The SqrtPrice before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return amountOut The amount of token0 that is swapped to.
     * @dev The calculations take both fees and slippage into account, but assume constant liquidity.
     */
    function _getAmount0OutFromAmount1In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount1)
        internal
        pure
        returns (uint256 amountOut)
    {
        unchecked {
            uint256 amountInLessFee = amount1.mulDivUp(1e6 - fee, 1e6);
            uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                sqrtPriceOld, usableLiquidity, amountInLessFee, true
            );
            amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
        }
    }

    /**
     * @notice Calculates the amountIn and amountOut of token0, for a given SqrtPrice after the swap.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The SqrtPrice before the swap.
     * @param sqrtPriceNew The SqrtPrice after the swap.
     * @return amountIn The amount of tokenIn.
     * @return amountOut The amount of tokenOut.
     * @dev The calculations take both fees and slippage into account, but assume constant liquidity.
     */
    function _getSwapParamsExact(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtPriceNew
    ) internal pure returns (uint256 amountIn, uint256 amountOut) {
        unchecked {
            if (zeroToOne) {
                uint256 amountInLessFee =
                    SqrtPriceMath.getAmount0Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, true);
                amountIn = amountInLessFee.mulDivUp(1e6, 1e6 - fee);
                amountOut = SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false);
            } else {
                uint256 amountInLessFee =
                    SqrtPriceMath.getAmount1Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, true);
                amountIn = amountInLessFee.mulDivUp(1e6, 1e6 - fee);
                amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
            }
        }
    }

    /**
     * @notice Approximates the amountIn and amountOut that maximise liquidity added,
     * given an approximation for the SqrtPrice after the swap and an approximation of the balances of token0 and token1 after the swap.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @param amountIn An approximation of the amount of tokenIn, used to calculate the approximated balances after the swap.
     * @param amountOut An approximation of the amount of tokenOut, used to calculate the approximated balances after the swap.
     * @param sqrtPrice An approximation of the SqrtPrice after the swap.
     * @return converged Bool indicating if the stop criterium of iteration is met.
     * @return amountIn_ The new approximation of the amount of tokenIn that maximise liquidity added.
     * @return amountOut_ The new approximation of the amount of amountOut that maximise liquidity added.
     */
    function _approximateOptimalSwapAmounts(
        bool zeroToOne,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPrice
    ) internal pure returns (bool, uint256, uint256) {
        unchecked {
            // Calculate the liquidity for the given approximated sqrtPrice and the approximated balances of token0 and token1 after the swap.
            uint256 liquidity0;
            uint256 liquidity1;
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

            // Calculate the relative difference of liquidity0 and liquidity1.
            uint256 relDiff = 1e18
                - (
                    liquidity0 < liquidity1
                        ? liquidity0.mulDivDown(1e18, liquidity1)
                        : liquidity1.mulDivDown(1e18, liquidity0)
                );
            // In the optimal solution liquidity0 equals liquidity1,
            // and there are no leftovers for token0 or token1 after minting the liquidity.
            // Hence the relative distance between liquidity0 and liquidity1
            // is a good estimator how close we are to the optimal solution.
            bool converged = relDiff < CONVERGENCE_THRESHOLD;

            // The new approximated liquidity is the minimum of liquidity0 and liquidity1.
            // Calculate the new approximated amountIn or amountOut,
            // for which this liquidity would be the optimal solution.
            if (liquidity0 < liquidity1) {
                uint256 amount1New = SqrtPriceMath.getAmount1Delta(
                    sqrtRatioLower, sqrtPrice, LiquidityAmounts.toUint128(liquidity0), true
                );
                zeroToOne
                    // Since amountOut can't be negative, we use 90% of the previous amountOut as a fallback.
                    ? amountOut = amount1New > amount1 ? amount1New - amount1 : amountOut.mulDivDown(9, 10)
                    : amountIn = amount1 - amount1New;
            } else {
                uint256 amount0New = SqrtPriceMath.getAmount0Delta(
                    sqrtPrice, sqrtRatioUpper, LiquidityAmounts.toUint128(liquidity1), true
                );
                zeroToOne
                    ? amountIn = amount0 - amount0New
                    // Since amountOut can't be negative, we use 90% of the previous amountOut as a fallback.
                    : amountOut = amount0New > amount0 ? amount0New - amount0 : amountOut.mulDivDown(9, 10);
            }

            return (converged, amountIn, amountOut);
        }
    }
}
