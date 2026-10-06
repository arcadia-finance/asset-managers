/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { QuadraticMath } from "./QuadraticMath.sol";
import { SqrtPriceMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { UnsafeMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/UnsafeMath.sol";

// forge-lint: disable-next-item(unsafe-typecast,boolean-cst,divide-before-multiply,cyclomatic-complexity)
library RebalanceOptimizationMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The maximal balance relative to the liquidity of the pool, with 192 binary precision.
    uint256 internal constant MAX_NORMALIZED = 1 << 252;

    // The binary precision of the coefficients.
    uint256 internal constant Q192 = 1 << 192;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error Overflow();

    /* //////////////////////////////////////////////////////////////
                              SWAP LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Analytically calculates the amountOut for a swap through the pool itself, that maximizes the amount of liquidity that is added.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return amountOut The amount of tokenOut.
     * @dev The calculations take both fees and slippage into account, but assume constant liquidity across the swap.
     * @dev Requires a nonzero usableLiquidity, and sqrtPriceOld above the lower tick for zeroToOne and below the upper tick otherwise.
     */
    function _getAmountOutWithSlippage(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 amountOut) {
        amountOut = zeroToOne
            ? _getAmount1OutWithSlippage(
                fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
            )
            : _getAmount0OutWithSlippage(
                fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
            );
    }

    /**
     * @notice Calculates the amountOut of token1 for a swap of token0, that maximizes the amount of liquidity that is added.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return amountOut The amount of token1.
     */
    function _getAmount1OutWithSlippage(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 amountOut) {
        uint256 amount0Start = amount0;
        uint160 sqrtPrice;
        // If the price is above the range, we sell all token0, unless that brings the price back into the range.
        if (sqrtPriceOld > sqrtRatioUpper) {
            uint256 amountInToBound;
            unchecked {
                amountInToBound = SqrtPriceMath.getAmount0Delta(sqrtRatioUpper, sqrtPriceOld, usableLiquidity, true)
                    .mulDivUp(1e6, 1e6 - fee);
            }
            if (amount0 < amountInToBound) {
                return _getAmount1OutFromAmount0In(fee, usableLiquidity, sqrtPriceOld, amount0);
            }
            // The price re-enters the range: we move it to the upper tick and solve the rest from there.
            amountOut = SqrtPriceMath.getAmount1Delta(sqrtRatioUpper, sqrtPriceOld, usableLiquidity, false);
            unchecked {
                amount0 -= amountInToBound;
            }
            amount1 += amountOut;
            sqrtPrice = sqrtRatioUpper;
        } else {
            sqrtPrice = sqrtPriceOld;
        }

        // Calculate the new sqrtPrice at which liquidity0 equals liquidity1.
        uint160 sqrtPriceNew =
            _getSqrtPrice(true, fee, usableLiquidity, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1);

        // Calculate the largest amountOut that reaches that sqrtPrice.
        unchecked {
            amountOut += SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPrice, usableLiquidity, false);
        }

        // Cap the amountOut where the pool would charge the whole balance of token0.
        amountOut =
            _capAmount1Out(fee, usableLiquidity, sqrtPriceOld, sqrtRatioUpper, sqrtPriceNew, amount0Start, amountOut);
    }

    /**
     * @notice Calculates the amountOut of token0 for a swap of token1, that maximizes the amount of liquidity that is added.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return amountOut The amount of token0.
     */
    function _getAmount0OutWithSlippage(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 amountOut) {
        uint256 amount1Start = amount1;
        uint160 sqrtPrice;
        // If the price is below the range, we sell all token1, unless that brings the price back into the range.
        if (sqrtPriceOld < sqrtRatioLower) {
            uint256 amountInToBound;
            unchecked {
                amountInToBound = SqrtPriceMath.getAmount1Delta(sqrtPriceOld, sqrtRatioLower, usableLiquidity, true)
                    .mulDivUp(1e6, 1e6 - fee);
            }
            if (amount1 < amountInToBound) {
                return _getAmount0OutFromAmount1In(fee, usableLiquidity, sqrtPriceOld, amount1);
            }
            // The price re-enters the range: we move it to the lower tick and solve the rest from there.
            amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtRatioLower, usableLiquidity, false);
            amount0 += amountOut;
            unchecked {
                amount1 -= amountInToBound;
            }
            sqrtPrice = sqrtRatioLower;
        } else {
            sqrtPrice = sqrtPriceOld;
        }

        // Calculate the new sqrtPrice at which liquidity0 equals liquidity1.
        uint160 sqrtPriceNew =
            _getSqrtPrice(false, fee, usableLiquidity, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1);

        // Calculate the largest amountOut that reaches that sqrtPrice.
        unchecked {
            amountOut += SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtPriceNew, usableLiquidity, false);
        }

        // Cap the amountOut where the pool would charge the whole balance of token1.
        amountOut =
            _capAmount0Out(fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtPriceNew, amount1Start, amountOut);
    }

    /**
     * @notice Calculates the amountOut of token1, for a given amountIn of token0.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The SqrtPrice before the swap.
     * @param amount0 The balance of token0 before the swap.
     * @return amountOut The amount of token1 that is swapped to.
     * @dev The net amountIn is rounded down, so the swap never costs more than amount0.
     */
    function _getAmount1OutFromAmount0In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount0)
        internal
        pure
        returns (uint256 amountOut)
    {
        unchecked {
            uint256 amountInLessFee = amount0.mulDiv(1e6 - fee, 1e6);
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
     * @dev The net amountIn is rounded down, so the swap never costs more than amount1.
     */
    function _getAmount0OutFromAmount1In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount1)
        internal
        pure
        returns (uint256 amountOut)
    {
        unchecked {
            uint256 amountInLessFee = amount1.mulDiv(1e6 - fee, 1e6);
            uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown(
                sqrtPriceOld, usableLiquidity, amountInLessFee, true
            );
            amountOut = SqrtPriceMath.getAmount0Delta(sqrtPriceOld, sqrtPriceNew, usableLiquidity, false);
        }
    }

    /* //////////////////////////////////////////////////////////////
                               CAP LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Caps the amountOut of token0, so that the swap leaves at least one wei of token1.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtPriceNew The sqrtPrice that amountOut reaches, with 96 binary precision.
     * @param amount1 The balance of token1 before the swap.
     * @param amountOut The amount of token0 that is swapped to.
     * @return amountOutCapped The capped amount of token0 that is swapped to.
     * @dev The pool rounds the net amountIn and the fee up, which can take the whole balance where the position needs less than two wei of token1.
     */
    function _capAmount0Out(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtPriceNew,
        uint256 amount1,
        uint256 amountOut
    ) internal pure returns (uint256 amountOutCapped) {
        amountOutCapped = amountOut;
        unchecked {
            // The largest net amountIn for which the pool, rounding it and the fee up, leaves one wei of token1.
            uint256 amount1LessFee = amount1.zeroFloorSub(1).fullMulDiv(1e6 - fee, 1e6);
            // The furthest sqrtPrice that amount1LessFee reaches, as the pool rounds it.
            uint256 sqrtPriceLimit = sqrtPriceOld + amount1LessFee.fullMulDiv(1 << 96, usableLiquidity);
            if (sqrtPriceNew > sqrtPriceLimit) {
                // Keep amountOut if it leaves one wei, else cap it at that sqrtPrice, but not below the lower tick.
                amountOutCapped = FixedPointMathLib.min(
                    amountOut,
                    SqrtPriceMath.getAmount0Delta(
                        sqrtPriceOld,
                        uint160(FixedPointMathLib.max(sqrtPriceLimit, sqrtRatioLower)),
                        usableLiquidity,
                        false
                    )
                );
            }
        }
    }

    /**
     * @notice Caps the amountOut of token1, so that the swap leaves at least one wei of token0.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param sqrtPriceNew The sqrtPrice that amountOut reaches, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amountOut The amount of token1 that is swapped to.
     * @return amountOutCapped The capped amount of token1 that is swapped to.
     * @dev The pool rounds the net amountIn and the fee up, which can take the whole balance where the position needs less than two wei of token0.
     */
    function _capAmount1Out(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioUpper,
        uint160 sqrtPriceNew,
        uint256 amount0,
        uint256 amountOut
    ) internal pure returns (uint256 amountOutCapped) {
        amountOutCapped = amountOut;
        unchecked {
            // The largest net amountIn for which the pool, rounding it and the fee up, leaves one wei of token0.
            uint256 amount0LessFee = amount0.zeroFloorSub(1).fullMulDiv(1e6 - fee, 1e6);
            // An upper bound of the pool's net amountIn to sqrtPriceNew.
            uint256 amountInLessFee = UnsafeMath.divRoundingUp(
                usableLiquidity * UnsafeMath.divRoundingUp(uint256(sqrtPriceOld - sqrtPriceNew) << 96, sqrtPriceOld),
                sqrtPriceNew
            );
            if (amountInLessFee > amount0LessFee) {
                // The furthest sqrtPrice that amount0LessFee reaches, as the pool rounds it, but not above the upper tick.
                sqrtPriceNew = uint160(
                    FixedPointMathLib.min(
                        SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
                            sqrtPriceOld, usableLiquidity, amount0LessFee, true
                        ),
                        sqrtRatioUpper
                    )
                );
                // Keep amountOut if it leaves one wei, else cap it at the largest amountOut that reaches that sqrtPrice.
                amountOutCapped = FixedPointMathLib.min(
                    amountOut, SqrtPriceMath.getAmount1Delta(sqrtPriceNew, sqrtPriceOld, usableLiquidity, false)
                );
            }
        }
    }

    /* //////////////////////////////////////////////////////////////
                           SQRT PRICE LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the new sqrtPrice after the swap that maximizes the amount of liquidity that is added.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return sqrtPriceNew The sqrtPrice at which liquidity0 equals liquidity1, with 96 binary precision.
     * @dev The price at which liquidity0 and liquidity1 are equal is found as follows:
     *  1) Both are rational functions of the square root price after the swap, s:
     *     L0 = b0 * s * Pu / (Pu − s)
     *     L1 = b1 / (s − Pl)
     *     With Pl and Pu the square root prices of the position range, and b0 and b1 the balances after the swap.
     *  2) The swap itself ties b0 and b1 to s through the pool equations, with a0 and a1 the balances before the
     *     swap, s0 the square root price before the swap, L the active liquidity and κ = 1 / (1 − fee):
     *     zeroToOne: b0 = a0 − κ * L * (1/s − 1/s0) and b1 = a1 + L * (s0 − s)
     *     oneToZero: b0 = a0 + L * (1/s0 − 1/s) and b1 = a1 − κ * L * (s − s0)
     *  3) Plugging 2) into 1) and equating clears both denominators and leaves a quadratic in s, so the price is a
     *     root of:
     *     A * s² + B * s + C = 0
     *  4) The coefficients of 3) reach 2^288, so the quadratic is solved in quantities normalized by s0 and L:
     *     p = Pl / s0, 1/q = s0 / Pu, α0 = a0 * s0 / L, α1 = a1 / (L * s0)
     *     and in the relative price move δ = |s − s0| / s0 rather than in s itself, since s ≈ s0 whenever the
     *     slippage is small and computing s first would cause a loss of precision on the move.
     */
    function _getSqrtPrice(
        bool zeroToOne,
        uint256 fee,
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint160 sqrtPriceNew) {
        (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) = _getQuadraticCoefficients(
            zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
        uint256 sqrtPriceDelta;
        if (zeroToOne) {
            // If liquidity1 already equals or exceeds liquidity0 at the start, we do not swap.
            if (constantCoefficient <= 0) return uint160(sqrtPriceOld);
            unchecked {
                sqrtPriceDelta = QuadraticMath._getRoot(quadraticCoefficient, linearCoefficient, constantCoefficient);
                // Round the sqrtPrice move down.
                sqrtPriceNew = uint160(sqrtPriceOld - sqrtPriceOld.fullMulDivN(sqrtPriceDelta, 192));
            }
        } else {
            // If liquidity0 already equals or exceeds liquidity1 at the start, we do not swap.
            if (constantCoefficient >= 0) return uint160(sqrtPriceOld);
            unchecked {
                sqrtPriceDelta = QuadraticMath._getRoot(-quadraticCoefficient, linearCoefficient, -constantCoefficient);
                // Round the sqrtPrice move down.
                sqrtPriceNew = uint160(sqrtPriceOld + sqrtPriceOld.fullMulDivN(sqrtPriceDelta, 192));
            }
        }
    }

    /**
     * @notice Calculates the quadratic in the relative move of the sqrtPrice, cleared of its denominators.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param fee The fee of the pool, with 6 decimals precision.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return quadraticCoefficient The quadratic coefficient, with 192 binary precision.
     * @return linearCoefficient The linear coefficient, with 192 binary precision.
     * @return constantCoefficient The constant coefficient, with 192 binary precision.
     * @dev zeroToOne: (α0 * m − κ * δ) * (m − p) = (α1 + δ) * (1 − m/q) with m = 1 − δ expands to A * δ² − B * δ + C = 0,
     *     A = α0 + κ − 1/q and B = α0 + (α0 + κ)(1 − p) + α1/q + (1 − 1/q)
     * @dev oneToZero: (α0 * m + δ) * (m − p) = (α1 − κ * δ) * (1 − m/q) with m = 1 + δ expands to A * δ² + B * δ + C = 0,
     *     A = α0 + 1 − κ/q and B = α0 + (α0 + 1)(1 − p) + α1/q + κ(1 − 1/q)
     * @dev In both, C = α0 * (1 − p) − α1 * (1 − 1/q).
     */
    function _getQuadraticCoefficients(
        bool zeroToOne,
        uint256 fee,
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        (
            uint256 amount0Normalized,
            uint256 amount1Normalized,
            uint256 sqrtRatioLowerNormalized,
            uint256 sqrtRatioUpperInverseNormalized
        ) = _getNormalizedParameters(usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1);

        unchecked {
            // C = α0 * (1 − p) − α1 * (1 − 1/q), with 1 − p and 1 − 1/q from the exact differences s0 − Pl, Pu − s0
            constantCoefficient = int256(
                amount0Normalized.fullMulDivUnchecked(sqrtPriceOld - sqrtRatioLower, sqrtPriceOld)
            ) - int256(amount1Normalized.fullMulDivUnchecked(sqrtRatioUpper - sqrtPriceOld, sqrtRatioUpper)); // 192 binary precision.

            // The ratio of the gross to the net amountIn: κ = 1 / (1 − fee)
            uint256 feeFactor = (1e6 << 192) / (1e6 - fee); // 192 binary precision.
            if (zeroToOne) {
                quadraticCoefficient = int256(amount0Normalized + feeFactor) - int256(sqrtRatioUpperInverseNormalized);
                linearCoefficient = 2 * quadraticCoefficient
                    + int256((amount1Normalized + Q192).fullMulDivN(sqrtRatioUpperInverseNormalized, 192) + Q192)
                    - int256((amount0Normalized + feeFactor).fullMulDivN(sqrtRatioLowerNormalized, 192) + feeFactor);
            } else {
                quadraticCoefficient =
                    int256(amount0Normalized + Q192) - int256(sqrtRatioUpperInverseNormalized * 1e6 / (1e6 - fee));
                linearCoefficient = 2 * quadraticCoefficient
                    + int256(
                        (amount1Normalized + feeFactor).fullMulDivN(sqrtRatioUpperInverseNormalized, 192) + feeFactor
                    ) - int256((amount0Normalized + Q192).fullMulDivN(sqrtRatioLowerNormalized, 192) + Q192);
            }
        }
    }

    /**
     * @notice Expresses the swap and position parameters as the dimensionless quantities the quadratic is written in.
     * @param usableLiquidity The amount of active liquidity in the pool, at the current tick.
     * @param sqrtPriceOld The square root of the pool price (token1/token0) before the swap, with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param amount0 The balance of token0 before the swap.
     * @param amount1 The balance of token1 before the swap.
     * @return amount0Normalized The balance of token0 relative to the liquidity of the pool, with 192 binary precision.
     * @return amount1Normalized The balance of token1 relative to the liquidity of the pool, with 192 binary precision.
     * @return sqrtRatioLowerNormalized The lower square root price relative to sqrtPriceOld, with 192 binary precision.
     * @return sqrtRatioUpperInverseNormalized The reciprocal of the upper square root price relative to sqrtPriceOld, with 192 binary precision.
     */
    function _getNormalizedParameters(
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    )
        internal
        pure
        returns (
            uint256 amount0Normalized,
            uint256 amount1Normalized,
            uint256 sqrtRatioLowerNormalized,
            uint256 sqrtRatioUpperInverseNormalized
        )
    {
        unchecked {
            // The range bounds relative to the price before the swap: p = Pl / s0 and 1/q = s0 / Pu,
            // each as ⌊n * 2^192 / d⌋ = ⌊n * 2^96 / d⌋ * 2^96 + ⌊(n * 2^96 mod d) * 2^96 / d⌋
            uint256 numerator = sqrtRatioLower << 96;
            sqrtRatioLowerNormalized =
                ((numerator / sqrtPriceOld) << 96) + (((numerator % sqrtPriceOld) << 96) / sqrtPriceOld); // 192 binary precision.
            numerator = sqrtPriceOld << 96;
            sqrtRatioUpperInverseNormalized =
                ((numerator / sqrtRatioUpper) << 96) + (((numerator % sqrtRatioUpper) << 96) / sqrtRatioUpper); // 192 binary precision.
        }

        // Both balances in units of the pool liquidity, dividing by L before s0: α0 = a0 * s0 / L, α1 = a1 / (L * s0)
        amount0Normalized = amount0.fullMulDiv(sqrtPriceOld << 96, usableLiquidity); // 192 binary precision.
        amount1Normalized = amount1.fullMulDiv(1 << 128, usableLiquidity).fullMulDiv(1 << 160, sqrtPriceOld); // 192 binary precision.
        if (amount0Normalized > MAX_NORMALIZED || amount1Normalized > MAX_NORMALIZED) revert Overflow();
    }
}
