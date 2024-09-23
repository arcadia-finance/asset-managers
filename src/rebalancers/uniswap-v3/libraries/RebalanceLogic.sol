/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../libraries/LiquidityAmounts.sol";
import { PricingLogic } from "./PricingLogic.sol";

library RebalanceLogic {
    using FixedPointMathLib for uint256;

    // The binary precision of sqrtPriceX96 squared.
    uint256 internal constant Q192 = PricingLogic.Q192;

    /**
     * @notice Returns the approximated swap parameters to optimize the total value that can be added as liquidity,
     * for a hypothetical swap without slippage and with fees.
     * @param balance0 The amount of token0 that is available for the rebalance.
     * @param balance1 The amount of token1 that is available for the rebalance.
     * @param initiatorFee The fee of the initiator.
     * @return zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @return amountIn The amount of tokenIn.
     * @dev Slippage is not taken into account when calculating the swap parameters.
     */
    function getRebalanceParams(
        uint256 maxSlippageRatio,
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
        returns (bool zeroToOne, uint256 amountIn, uint256 amountOut, uint256 amountInitiatorFee, uint256 minLiquidity)
    {
        // Total fee is pool fee + initiator fee, with 18 decimals precision.
        // Since Uniswap uses 6 decimals precision for the fee, we have to multiply the pool fee by 1e12.
        uint256 fee = initiatorFee + poolFee * 1e12;
        if (sqrtPrice >= sqrtRatioUpper) {
            // Position is out of range and fully in token 1.
            // Swap full amount of token0 to token1.
            zeroToOne = true;
            amountIn = balance0;
            amountOut = _getAmountOut(sqrtPrice, true, balance0, fee);
        } else if (sqrtPrice <= sqrtRatioLower) {
            // Position is out of range and fully in token 0.
            // Swap full amount of token1 to token0.
            amountIn = balance1;
            amountOut = _getAmountOut(sqrtPrice, false, balance1, fee);
        } else {
            // Get target ratio in token1 terms.
            uint256 targetRatio = _getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);

            // Calculate the total position value in token1 equivalent:
            uint256 token0ValueInToken1 = PricingLogic._getSpotValue(sqrtPrice, true, balance0);
            uint256 totalValueInToken1 = balance1 + token0ValueInToken1;
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

        // Calculate the maximum amount of liquidity that can be added to the position.
        {
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                uint160(sqrtPrice),
                uint160(sqrtRatioLower),
                uint160(sqrtRatioUpper),
                zeroToOne ? balance0 - amountIn : balance0 + amountOut,
                zeroToOne ? balance1 + amountOut : balance1 - amountIn
            );
            minLiquidity = liquidity.mulDivDown(maxSlippageRatio, 1e18);
        }

        // Get initiator fee amount and the actual amountIn of the swap (without initiator fee).
        amountInitiatorFee = amountIn.mulDivDown(initiatorFee, 1e18);
        amountIn = amountIn - amountInitiatorFee;
    }

    /**
     * @notice Calculates the amountOut for a given amountIn and sqrtPriceX96 for a hypothetical
     * swap without slippage and with fees.
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountIn The amount that of tokenIn that must be swapped to tokenOut.
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
        uint256 amountInWithoutFees = (1e18 - fee).mulDivDown(amountIn, 1e18);
        amountOut = zeroToOne
            ? FullMath.mulDiv(amountInWithoutFees, sqrtPriceX96 ** 2, Q192)
            : FullMath.mulDiv(amountInWithoutFees, Q192, sqrtPriceX96 ** 2);
    }

    /**
     * @notice Calculates the amountIn for a given amountOut and sqrtPriceX96 for a hypothetical
     * swap with fees but without slippage (we assume a pool with infinite liquidity).
     * @param sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped.
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
        uint256 amountInWithoutFees = zeroToOne
            ? FullMath.mulDiv(amountOut, Q192, sqrtPriceX96 ** 2)
            : FullMath.mulDiv(amountOut, sqrtPriceX96 ** 2, Q192);
        amountIn = amountInWithoutFees.mulDivDown(1e18, 1e18 - fee);
    }

    /**
     * @notice Calculates the ratio of how much of the total value of a liquidity position has to be provided in token1.
     * @param sqrtPriceX96 The square root of the current pool price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position.
     * @return targetRatio The ratio of the value of token1 compared to the total value of the position, with 18 decimals precision.
     * @dev Function will revert for all pools where the sqrtPriceX96 is bigger than type(uint128).max.
     * type(uint128).max is currently more than enough for all supported pools.
     * If ever the sqrtPriceX96 of a pool exceeds type(uint128).max, a different rebalancer has to be deployed,
     * which does two consecutive mulDivs.
     * @dev Derivation of the formula:
     * 1) The ratio is defined as:
     *    R = valueToken1 / (valueToken0 + valueToken1)
     *    If we express all values in token1 en use the current pool price to denominate token0 in token1:
     *    R = amount1 / (amount0 * sqrtPrice² + amount1)
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
        uint256 numerator = sqrtPriceX96 - sqrtRatioLower;
        uint256 denominator = 2 * sqrtPriceX96 - sqrtRatioLower - sqrtPriceX96 ** 2 / sqrtRatioUpper;

        targetRatio = numerator.mulDivDown(1e18, denominator);
    }
}
