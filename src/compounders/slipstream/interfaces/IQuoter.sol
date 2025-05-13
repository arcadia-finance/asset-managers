// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

struct QuoteExactOutputSingleParams {
    address tokenIn;
    address tokenOut;
    uint256 amount;
    int24 tickSpacing;
    uint160 sqrtPriceLimitX96;
}

interface IQuoter {
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceAfter, uint32 initializedTicksCrossed, uint256 gasEstimate);
}
