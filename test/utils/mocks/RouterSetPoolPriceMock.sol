/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

interface IUniswapV3PoolExtension {
    function setSqrtPrice(uint160 sqrtPrice) external;
}

contract RouterSetPoolPriceMock {
    function swap(address pool, uint160 sqrtPrice) external {
        IUniswapV3PoolExtension(pool).setSqrtPrice(sqrtPrice);
    }
}
