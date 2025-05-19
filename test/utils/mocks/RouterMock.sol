/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";

contract RouterMock {
    error EthTransferFailed();

    event ArbitrarySwap(bool);

    constructor() { }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) public {
        if (tokenIn != address(0)) {
            ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        }

        if (tokenOut == address(0)) {
            (bool success,) = payable(msg.sender).call{ value: amountOut }("");
            if (!success) revert EthTransferFailed();
        } else {
            ERC20(tokenOut).transfer(msg.sender, amountOut);
        }

        emit ArbitrarySwap(true);
    }

    function swap2(address token0, address token1, uint256 amount0, uint256 amount1) public {
        if (token0 == address(0)) {
            (bool success,) = payable(msg.sender).call{ value: amount0 }("");
            if (!success) revert EthTransferFailed();
        } else {
            ERC20(token0).transfer(msg.sender, amount0);
        }

        ERC20(token1).transfer(msg.sender, amount1);

        emit ArbitrarySwap(true);
    }
}
