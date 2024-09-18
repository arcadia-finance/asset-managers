/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { NoSlippageSwapMath } from "../../../src/rebalancers/uniswap-v3/libraries/NoSlippageSwapMath.sol";
import { UniswapV3Rebalancer } from "../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/uniswap-v3/libraries/UniswapV3Logic.sol";

contract UniswapV3RebalancerExtension is UniswapV3Rebalancer {
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio)
        UniswapV3Rebalancer(maxTolerance, maxInitiatorFee, maxSlippageRatio)
    { }

    function getSwapParams(
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) public pure returns (bool zeroToOne, uint256 amountIn, uint256 amountOut, uint256 amountInitiatorFee) {
        return NoSlippageSwapMath.getSwapParams(
            poolFee, initiatorFee, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
    }

    function getSwapParams(
        UniswapV3RebalancerExtension.PositionState memory position,
        uint256 amount0,
        uint256 amount1,
        uint256 initiatorFee
    ) public pure returns (bool zeroToOne, uint256 amountIn, uint256 amountOut, uint256 amountInitiatorFee) {
        return NoSlippageSwapMath.getSwapParams(
            position.fee,
            initiatorFee,
            position.sqrtPriceX96,
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            amount0,
            amount1
        );
    }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut, bytes memory swapData) external {
        _swap(position, zeroToOne, amountOut, swapData);
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
