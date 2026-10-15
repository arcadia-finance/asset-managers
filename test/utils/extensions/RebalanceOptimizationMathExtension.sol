/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalanceOptimizationMath } from "../../../src/cl-managers/libraries/RebalanceOptimizationMath.sol";

contract RebalanceOptimizationMathExtension {
    function getAmountOutWithSlippage(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint256) {
        return RebalanceOptimizationMath.getAmountOutWithSlippage(
            zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
    }

    function getAmountOutFromAmountIn(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint256 amountIn
    ) external pure returns (uint256 amountOut) {
        amountOut = RebalanceOptimizationMath._getAmountOutFromAmountIn(
            zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn
        );
    }

    function getSqrtPrice(
        bool zeroToOne,
        uint256 fee,
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = RebalanceOptimizationMath._getSqrtPrice(
            zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
    }

    function getQuadraticCoefficients(
        bool zeroToOne,
        uint256 fee,
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) external pure returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient) {
        (quadraticCoefficient, linearCoefficient, constantCoefficient) =
            RebalanceOptimizationMath._getQuadraticCoefficients(
                zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
            );
    }

    function getNormalizedParameters(
        uint256 usableLiquidity,
        uint256 sqrtPriceOld,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    )
        external
        pure
        returns (
            uint256 amount0Normalized,
            uint256 amount1Normalized,
            uint256 sqrtRatioLowerNormalized,
            uint256 sqrtRatioUpperInverseNormalized
        )
    {
        (
            amount0Normalized, amount1Normalized, sqrtRatioLowerNormalized, sqrtRatioUpperInverseNormalized
        ) =
            RebalanceOptimizationMath._getNormalizedParameters(
                usableLiquidity, sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
            );
    }
}
