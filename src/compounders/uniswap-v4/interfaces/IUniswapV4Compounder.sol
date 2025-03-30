/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

struct PositionState {
    uint256 sqrtPriceX96;
    uint256 sqrtRatioLower;
    uint256 sqrtRatioUpper;
    uint256 lowerBoundSqrtPriceX96;
    uint256 upperBoundSqrtPriceX96;
}

struct Fees {
    uint256 amount0;
    uint256 amount1;
}

interface IUniswapV4Compounder {
    function getSwapParameters(PositionState memory position, Fees memory fees)
        external
        view
        returns (bool zeroToOne, uint256 amountOut);

    function getPositionState(uint256 id, uint256 trustedSqrtPriceX96, address initiator)
        external
        view
        returns (PositionState memory position);

    function isPoolUnbalanced(PositionState memory position) external view returns (bool isPoolUnbalanced_);

    function initiatorInfo(address) external returns (uint64, uint64, uint64);
    function accountToInitiator(address) external returns (address);
}
