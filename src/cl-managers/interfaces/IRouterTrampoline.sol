/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

interface IRouterTrampoline {
    function execute(address router, bytes calldata callData, address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 balanceIn, uint256 balanceOut);
}
