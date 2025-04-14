/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceLogic } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";

contract RebalanceLogicExtension {
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
        external
        pure
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic._getRebalanceParams(
            maxSlippageRatio, poolFee, initiatorFee, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1
        );
    }

    function getSwapParams(
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1,
        uint256 fee
    ) external pure returns (bool zeroToOne, uint256 amountIn, uint256 amountOut) {
        return RebalanceLogic._getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);
    }

    function getAmountOut(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountIn, uint256 fee)
        external
        pure
        returns (uint256 amountOut)
    {
        return RebalanceLogic._getAmountOut(sqrtPriceX96, zeroToOne, amountIn, fee);
    }

    function getAmountIn(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountOut, uint256 fee)
        external
        pure
        returns (uint256 amountIn)
    {
        return RebalanceLogic._getAmountIn(sqrtPriceX96, zeroToOne, amountOut, fee);
    }

    function getTargetRatio(uint256 sqrtPriceX96, uint256 sqrtRatioLower, uint256 sqrtRatioUpper)
        external
        pure
        returns (uint256 targetRatio)
    {
        return RebalanceLogic._getTargetRatio(sqrtPriceX96, sqrtRatioLower, sqrtRatioUpper);
    }
}
