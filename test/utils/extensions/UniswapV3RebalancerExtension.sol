/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { PricingLogic } from "../../../src/rebalancers/uniswap-v3/libraries/PricingLogic.sol";
import { RebalanceLogic } from "../../../src/rebalancers/uniswap-v3/libraries/RebalanceLogic.sol";
import { UniswapV3Rebalancer } from "../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";

contract UniswapV3RebalancerExtension is UniswapV3Rebalancer {
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio)
        UniswapV3Rebalancer(maxTolerance, maxInitiatorFee, maxSlippageRatio)
    { }

    function getRebalanceParams(
        uint256 maxSlippageRatio,
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    )
        public
        pure
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic.getRebalanceParams(
            maxSlippageRatio, poolFee, initiatorFee, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
    }

    function getRebalanceParams(
        UniswapV3RebalancerExtension.PositionState memory position,
        uint256 amount0,
        uint256 amount1,
        uint256 initiatorFee
    )
        public
        view
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic.getRebalanceParams(
            UniswapV3Rebalancer.MAX_SLIPPAGE_RATIO,
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
        return PricingLogic._getSqrtPriceX96(priceToken0, priceToken1);
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
