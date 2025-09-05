// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IUniswapV3Pool {
    function liquidity() external view returns (uint128 liquidity);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPrice,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function tickSpacing() external view returns (int24 tickSpacing);
}
