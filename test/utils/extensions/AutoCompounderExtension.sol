/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder } from "../../../src/auto-compounder/AutoCompounder.sol";
import { UniswapV3Logic } from "../../../src/auto-compounder/libraries/UniswapV3Logic.sol";

contract AutoCompounderExtension is AutoCompounder {
    constructor(uint256 minUsdFeeValue, uint256 initiatorFee, uint256 tolerance)
        AutoCompounder(minUsdFeeValue, initiatorFee, tolerance)
    { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, Fees memory fees, bool zeroToOne, int256 amountIn)
        public
        returns (bool, Fees memory)
    {
        return _swap(position, fees, zeroToOne, amountIn);
    }
}
