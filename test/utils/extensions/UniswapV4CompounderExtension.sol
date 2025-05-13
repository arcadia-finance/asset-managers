/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { UniswapV4Compounder } from "../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Logic } from "../../../src/compounders/uniswap-v4/libraries/UniswapV4Logic.sol";

contract UniswapV4CompounderExtension is UniswapV4Compounder {
    constructor(uint256 maxTolerance, uint256 maxInitiatorShare) UniswapV4Compounder(maxTolerance, maxInitiatorShare) { }

    function getSqrtPrice(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV4Logic._getSqrtPrice(priceToken0, priceToken1);
    }

    function swap(
        PoolKey memory poolKey,
        uint256 lowerBoundSqrtPrice,
        uint256 upperBoundSqrtPrice,
        bool zeroToOne,
        uint256 amountOut
    ) public returns (bool) {
        return _swap(poolKey, lowerBoundSqrtPrice, upperBoundSqrtPrice, zeroToOne, amountOut);
    }

    function collectFees(uint256 tokenId, PoolKey memory poolKey)
        internal
        returns (uint256 feeAmount0, uint256 feeAmount1)
    {
        return _collectFees(tokenId, poolKey);
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
