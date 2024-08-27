// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.22;

struct QuoteExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    uint256 amountOut;
    uint24 fee;
    uint160 sqrtPriceLimitX96;
}

struct QuoteExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint24 fee;
    uint160 sqrtPriceLimitX96;
}

interface IQuoter {
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}
