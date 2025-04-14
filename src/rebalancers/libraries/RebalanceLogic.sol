/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "../libraries/uniswap-v3/LiquidityAmounts.sol";
import { PricingLogic } from "./PricingLogic.sol";

library RebalanceLogic {
    using FixedPointMathLib for uint256;

    // The binary precision of sqrtPriceX96 squared.
    uint256 internal constant Q192 = PricingLogic.Q192;

    /**
     * @notice Returns the parameters and constraints to rebalance the position.
     * Both parameters and constraints are calculated based on a hypothetical swap (in the pool itself with fees but without slippage),
     * that maximizes the amount of liquidity that can be added to the positions (no leftovers of either token0 or token1).
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param poolFee The fee of the pool, with 6 decimals precision.
     * @param initiatorFee The fee of the initiator, with 18 decimals precision.
     * @param sqrtPrice The square root of the price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param balance0 The amount of token0 that is available for the rebalance.
     * @param balance1 The amount of token1 that is available for the rebalance.
     * @return minLiquidity The minimum amount of liquidity that must be added to the position.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountInitiatorFee The amount of initiator fee, in tokenIn.
     * @return amountIn An approximation of the amount of tokenIn, based on the optimal swap through the pool itself without slippage.
     * @return amountOut An approximation of the amount of tokenOut, based on the optimal swap through the pool itself without slippage.
     */
    function _getRebalanceParams(
        uint256 minLiquidityRatio,
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1
    )
        internal
        pure
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        // Total fee is pool fee + initiator fee, with 18 decimals precision.
        // Since Uniswap uses 6 decimals precision for the fee, we have to multiply the pool fee by 1e12.
        uint256 fee;
        unchecked {
            fee = initiatorFee + poolFee * 1e12;
        }

        // Calculate the swap parameters
        (zeroToOne, amountIn, amountOut) =
            _getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Calculate the maximum amount of liquidity that can be added to the position.
        {
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                uint160(sqrtPrice),
                uint160(sqrtRatioLower),
                uint160(sqrtRatioUpper),
                zeroToOne ? balance0 - amountIn : balance0 + amountOut,
                zeroToOne ? balance1 + amountOut : balance1 - amountIn
            );
            minLiquidity = liquidity.mulDivDown(minLiquidityRatio, 1e18);
        }

        // Get initiator fee amount and the actual amountIn of the swap (without initiator fee).
        unchecked {
            amountInitiatorFee = amountIn.mulDivDown(initiatorFee, 1e18);
            amountIn = amountIn - amountInitiatorFee;
        }
    }

    /**
     * @notice Calculates the swap parameters, calculated based on a hypothetical swap (in the pool itself with fees but without slippage).
     * that maximizes the amount of liquidity that can be added to the positions (no leftovers of either token0 or token1).
     * @param sqrtPrice The square root of the price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param balance0 The amount of token0 that is available for the rebalance.
     * @param balance1 The amount of token1 that is available for the rebalance.
     * @param fee The swapping fees, with 18 decimals precision.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountIn An approximation of the amount of tokenIn, based on the optimal swap through the pool itself without slippage.
     * @return amountOut An approximation of the amount of tokenOut, based on the optimal swap through the pool itself without slippage.
     * @dev The swap parameters are derived as follows:
     * 1) First we check if the position is in or out of range.
     *   - If the current price is above the position, the solution is trivial: we swap the full position to token1.
     *   - If the current price is below the position, similar, we swap the full position to token0.
     *   - If the position is in range we proceed with step 2.
     *
     * 2) If the position is in range, we start with calculating the "Target Ratio" and "Current Ratio".
     *    Both ratio's are defined as the value of the amount of token1 compared to the total value of the position:
     *    R = valueToken1 / [valueToken0 + valueToken1]
     *    If we express all values in token1 and use the current pool price to denominate token0 in token1:
     *    R = amount1 / [amount0 * sqrtPrice² + amount1]
     *
     *    a) The "Target Ratio" (R_target) is the ratio of the new liquidity position.
     *       It is calculated with the current price and the upper and lower prices of the liquidity position,
     *       see _getTargetRatio() for the derivation.
     *       To maximise the liquidity of the new position, the balances after the swap should approximate it as close as possible to not have any leftovers.
     *    b) The "Current Ratio" (R_current) is the ratio of the current token balances, it is calculated as follows:
     *       R_current = balance1 / [balance0 * sqrtPrice² + balance1].
     *
     * 3) From R_target and R_current we can finally derive the direction of the swap, amountIn and amountOut.
     *    If R_current is smaller than R_target, we have to swap an amount of token0 to token1, and vice versa.
     *    amountIn and amountOut can be found by solving the following equalities:
     *      a) The ratio of the token balances after the swap equal the "Target Ratio".
     *      b) The swap between token0 and token1 is done in the pool itself,
     *         taking into account fees, but ignoring slippage (-> sqrtPrice remains constant).
     *
     *    If R_current < R_target (swap token0 to token1):
     *      a) R_target = [amount1 + amoutOut] / [(amount0 - amountIn) * sqrtPrice² + (amount1 + amoutOut)].
     *      b) amountOut = (1 - fee) * amountIn * sqrtPrice².
     *         => amountOut = [(R_target - R_current) * (amount0 * sqrtPrice² + amount1)] / [1 + R_target * fee / (1 - fee)].
     *
     *    If R_current > R_target (swap token1 to token0):
     *      a) R_target = [(amount1 - amountIn)] / [(amount0 + amoutOut) * sqrtPrice² + (amount1 - amountIn)].
     *      b) amountOut = (1 - fee) * amountIn / sqrtPrice².
     *         => amountIn = [(R_current - R_target) * (amount0 * sqrtPrice² + amount1)] / (1 - R_target * fee).
     */
    function _getSwapParams(
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1,
        uint256 fee
    ) internal pure returns (bool zeroToOne, uint256 amountIn, uint256 amountOut) {
        if (sqrtPrice >= sqrtRatioUpper) {
            // New position is out of range and fully in token 1.
            // Rebalance to a single-sided liquidity position in token 1.
            zeroToOne = true;
            amountIn = balance0;
            amountOut = _getAmountOut(sqrtPrice, true, balance0, fee);
        } else if (sqrtPrice <= sqrtRatioLower) {
            // New position is out of range and fully in token 0.
            // Rebalance to a single-sided liquidity position in token 0.
            amountIn = balance1;
            amountOut = _getAmountOut(sqrtPrice, false, balance1, fee);
        } else {
            // Get target ratio in token1 terms.
            uint256 targetRatio = _getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);

            // Calculate the total position value in token1 equivalent:
            uint256 token0ValueInToken1 = PricingLogic._getSpotValue(sqrtPrice, true, balance0);
            uint256 totalValueInToken1 = balance1 + token0ValueInToken1;

            unchecked {
                // Calculate the current ratio of liquidity in token1 terms.
                uint256 currentRatio = balance1.mulDivDown(1e18, totalValueInToken1);
                if (currentRatio < targetRatio) {
                    // Swap token0 partially to token1.
                    zeroToOne = true;
                    {
                        uint256 denominator = 1e18 + targetRatio.mulDivDown(fee, 1e18 - fee);
                        amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, denominator);
                    }
                    amountIn = _getAmountIn(sqrtPrice, true, amountOut, fee);
                } else {
                    // Swap token1 partially to token0.
                    zeroToOne = false;
                    {
                        uint256 denominator = 1e18 - targetRatio.mulDivDown(fee, 1e18);
                        amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, denominator);
                    }
                    amountOut = _getAmountOut(sqrtPrice, false, amountIn, fee);
                }
            }
        }
    }

    /**
     * @notice Calculates the amountOut for a given amountIn and sqrtPriceX96 for a hypothetical
     * swap though the pool itself with fees but without slippage.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount of tokenIn that must be swapped to tokenOut.
     * @param fee The total fee on amountIn, with 18 decimals precision.
     * @return amountOut The amount of tokenOut.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different rebalancer has to be deployed,
     * which does two consecutive mulDivs.
     */
    function _getAmountOut(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountIn, uint256 fee)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(sqrtPriceX96 <= type(uint128).max);
        unchecked {
            uint256 amountInWithoutFees = (1e18 - fee).mulDivDown(amountIn, 1e18);
            amountOut = zeroToOne
                ? FullMath.mulDiv(amountInWithoutFees, sqrtPriceX96 ** 2, Q192)
                : FullMath.mulDiv(amountInWithoutFees, Q192, sqrtPriceX96 ** 2);
        }
    }

    /**
     * @notice Calculates the amountIn for a given amountOut and sqrtPriceX96 for a hypothetical
     * swap though the pool itself with fees but without slippage.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that tokenOut that must be swapped.
     * @param fee The total fee on amountIn, with 18 decimals precision.
     * @return amountIn The amount of tokenIn.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different rebalancer has to be deployed,
     * which does two consecutive mulDivs.
     */
    function _getAmountIn(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountOut, uint256 fee)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(sqrtPriceX96 <= type(uint128).max);
        unchecked {
            uint256 amountInWithoutFees = zeroToOne
                ? FullMath.mulDiv(amountOut, Q192, sqrtPriceX96 ** 2)
                : FullMath.mulDiv(amountOut, sqrtPriceX96 ** 2, Q192);
            amountIn = amountInWithoutFees.mulDivDown(1e18, 1e18 - fee);
        }
    }

    /**
     * @notice Calculates the ratio of how much of the total value of a liquidity position has to be provided in token1.
     * @param sqrtPriceX96 The square root of the current pool price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @return targetRatio The ratio of the value of token1 compared to the total value of the position, with 18 decimals precision.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different rebalancer has to be deployed,
     * which does two consecutive mulDivs.
     * @dev Derivation of the formula:
     * 1) The ratio is defined as:
     *    R = valueToken1 / [valueToken0 + valueToken1]
     *    If we express all values in token1 and use the current pool price to denominate token0 in token1:
     *    R = amount1 / [amount0 * sqrtPrice² + amount1]
     * 2) Amount0 for a given liquidity position of a Uniswap V3 pool is given as:
     *    Amount0 = liquidity * (sqrtRatioUpper - sqrtPrice) / (sqrtRatioUpper * sqrtPrice)
     * 3) Amount1 for a given liquidity position of a Uniswap V3 pool is given as:
     *    Amount1 = liquidity * (sqrtPrice - sqrtRatioLower)
     * 4) Combining 1), 2) and 3) and simplifying we get:
     *    R = [sqrtPrice - sqrtRatioLower] / [2 * sqrtPrice - sqrtRatioLower - sqrtPrice² / sqrtRatioUpper]
     */
    function _getTargetRatio(uint256 sqrtPriceX96, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        internal
        pure
        returns (uint256 targetRatio)
    {
        require(sqrtPriceX96 <= type(uint128).max);
        // Unchecked: sqrtPriceX96 is always bigger than sqrtRatioLower.
        // Unchecked: sqrtPriceX96 is always smaller than sqrtRatioUpper -> sqrtPriceX96 > sqrtPriceX96 ** 2 / sqrtRatioUpper.
        unchecked {
            uint256 numerator = sqrtPriceX96 - sqrtRatioLower;
            uint256 denominator = 2 * sqrtPriceX96 - sqrtRatioLower - sqrtPriceX96 ** 2 / sqrtRatioUpper;

            targetRatio = numerator.mulDivDown(1e18, denominator);
        }
    }
}
