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
}
