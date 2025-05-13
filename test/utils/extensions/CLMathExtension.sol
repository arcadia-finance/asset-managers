/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CLMath } from "../../../src/libraries/CLMath.sol";

contract CLMathExtension {
    function getSwapParams(
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1,
        uint256 fee
    ) external pure returns (bool zeroToOne, uint256 amountIn, uint256 amountOut) {
        return CLMath._getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);
    }

    function getSpotValue(uint256 sqrtPrice, bool zeroToOne, uint256 amountIn)
        external
        pure
        returns (uint256 amountOut)
    {
        return CLMath._getSpotValue(sqrtPrice, zeroToOne, amountIn);
    }

    function getAmountOut(uint256 sqrtPrice, bool zeroToOne, uint256 amountIn, uint256 fee)
        external
        pure
        returns (uint256 amountOut)
    {
        return CLMath._getAmountOut(sqrtPrice, zeroToOne, amountIn, fee);
    }

    function getAmountIn(uint256 sqrtPrice, bool zeroToOne, uint256 amountOut, uint256 fee)
        external
        pure
        returns (uint256 amountIn)
    {
        return CLMath._getAmountIn(sqrtPrice, zeroToOne, amountOut, fee);
    }

    function getTargetRatio(uint256 sqrtPrice, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        external
        pure
        returns (uint256 targetRatio)
    {
        return CLMath._getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
    }
}
