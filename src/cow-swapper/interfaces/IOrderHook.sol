/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.0;

interface IOrderHook {
    function setHook(address account, bytes calldata hookData) external;
    function getInitiatorParams(address account, address tokenIn, uint256 amountIn, bytes calldata initiatorData)
        external
        view
        returns (uint64 swapFee, address tokenOut, bytes32 orderHash);
}
