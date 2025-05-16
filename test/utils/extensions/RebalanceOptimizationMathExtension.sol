/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceOptimizationMath } from "../../../src/libraries/RebalanceOptimizationMath.sol";

contract RebalanceOptimizationMathExtension {
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
    ) external pure returns (uint256) {
        return RebalanceOptimizationMath._getAmountOutWithSlippage(
            zeroToOne,
            fee,
            usableLiquidity,
            sqrtPriceOld,
            sqrtRatioLower,
            sqrtRatioUpper,
            amount0,
            amount1,
            amountIn,
            amountOut
        );
    }

    function approximateSqrtPriceNew(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint256 amountIn,
        uint256 amountOut
    ) external pure returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = RebalanceOptimizationMath._approximateSqrtPriceNew(
            zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn, amountOut
        );
    }

    function getAmount1OutFromAmount0In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount0)
        external
        pure
        returns (uint256 amountOut)
    {
        amountOut = RebalanceOptimizationMath._getAmount1OutFromAmount0In(fee, usableLiquidity, sqrtPriceOld, amount0);
    }

    function getAmount0OutFromAmount1In(uint256 fee, uint128 usableLiquidity, uint160 sqrtPriceOld, uint256 amount1)
        external
        pure
        returns (uint256 amountOut)
    {
        amountOut = RebalanceOptimizationMath._getAmount0OutFromAmount1In(fee, usableLiquidity, sqrtPriceOld, amount1);
    }

    function getSwapParamsExact(
        bool zeroToOne,
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint160 sqrtPriceNew
    ) external pure returns (uint256 amountIn, uint256 amountOut) {
        (amountIn, amountOut) =
            RebalanceOptimizationMath._getSwapParamsExact(zeroToOne, fee, usableLiquidity, sqrtPriceOld, sqrtPriceNew);
    }

    function approximateOptimalSwapAmounts(
        bool zeroToOne,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1,
        uint256 amountIn,
        uint256 amountOut,
        uint160 sqrtPrice
    ) external pure returns (bool converged, uint256 amountIn_, uint256 amountOut_) {
        (converged, amountIn_, amountOut_) = RebalanceOptimizationMath._approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );
    }
}
