/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3AutoCompounder } from "../../../src/auto-compounders/uniswap-v3/UniswapV3AutoCompounder.sol";
import { UniswapV3Logic } from "../../../src/auto-compounders/uniswap-v3/libraries/UniswapV3Logic.sol";

contract UniswapV3AutoCompounderExtension is UniswapV3AutoCompounder {
    constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        UniswapV3AutoCompounder(compoundThreshold, initiatorShare, tolerance)
    { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }
}
