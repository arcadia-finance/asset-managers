/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

interface IOrderHook {
    function setHook(address account, bytes calldata hookData) external;
    function getOrderData(address account, bytes calldata hookData)
        external
        view
        returns (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut, uint32 validTo);
}
