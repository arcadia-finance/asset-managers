/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

struct PositionState {
    address pool;
    address token0;
    address token1;
    uint24 fee;
    uint256 sqrtPrice;
    uint256 sqrtRatioLower;
    uint256 sqrtRatioUpper;
    uint256 lowerBoundSqrtPrice;
    uint256 upperBoundSqrtPrice;
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

    function getPositionState(uint256 id, uint256 trustedSqrtPrice, address initiator)
        external
        view
        returns (PositionState memory position);

    function isPoolUnbalanced(PositionState memory position) external view returns (bool isPoolUnbalanced_);

    function initiatorInfo(address) external returns (uint64, uint64, uint64);
    function accountToInitiator(address) external returns (address);
}
