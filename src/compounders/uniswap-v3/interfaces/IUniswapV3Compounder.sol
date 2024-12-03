/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

struct PositionState {
    address pool;
    address token0;
    address token1;
    uint24 fee;
    uint256 sqrtPriceX96;
    uint256 sqrtRatioLower;
    uint256 sqrtRatioUpper;
    uint256 lowerBoundSqrtPriceX96;
    uint256 upperBoundSqrtPriceX96;
    uint256 usdPriceToken0;
    uint256 usdPriceToken1;
}

struct Fees {
    uint256 amount0;
    uint256 amount1;
}

interface IUniswapV3Compounder {
    function getSwapParameters(PositionState memory position, Fees memory fees)
        external
        view
        returns (bool zeroToOne, uint256 amountOut);

    function getPositionState(uint256 id) external view returns (PositionState memory position);

    function isBelowThreshold(PositionState memory position, Fees memory fees)
        external
        view
        returns (bool isBelowThreshold_);

    function isPoolUnbalanced(PositionState memory position) external view returns (bool isPoolUnbalanced_);

    function COMPOUND_THRESHOLD() external view returns (uint256);

    function INITIATOR_SHARE() external view returns (uint256);
}
