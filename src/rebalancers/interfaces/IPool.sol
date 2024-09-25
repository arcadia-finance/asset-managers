// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.22;

interface IPool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function liquidity() external view returns (uint128 liquidity);
}
