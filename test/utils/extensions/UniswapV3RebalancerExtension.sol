/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3Rebalancer } from "../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Logic } from "../../../src/libraries/UniswapV3Logic.sol";

contract UniswapV3RebalancerExtension is UniswapV3Rebalancer {
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee) UniswapV3Rebalancer(maxTolerance, maxInitiatorFee) { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
