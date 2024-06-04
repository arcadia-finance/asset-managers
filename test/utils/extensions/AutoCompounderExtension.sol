/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder } from "../../../src/auto-compounder/AutoCompounder.sol";
import { UniswapV3Logic } from "../../../src/auto-compounder/libraries/UniswapV3Logic.sol";

contract AutoCompounderExtension is AutoCompounder {
    constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        AutoCompounder(compoundThreshold, initiatorShare, tolerance)
    { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return UniswapV3Logic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }

    function getSwapParameters(PositionState memory position, Fees memory fees)
        public
        pure
        returns (bool zeroToOne, uint256 amountOut)
    {
        (zeroToOne, amountOut) = _getSwapParameters(position, fees);
    }

    function getPositionState(uint256 tokenId) public view returns (PositionState memory position) {
        position = _getPositionState(tokenId);
    }

    function isBelowThreshold(PositionState memory position, Fees memory fees)
        public
        view
        returns (bool isBelowThreshold_)
    {
        isBelowThreshold_ = _isBelowThreshold(position, fees);
    }

    function isPoolUnbalanced(PositionState memory position) public pure returns (bool isPoolUnbalanced_) {
        isPoolUnbalanced_ = _isPoolUnbalanced(position);
    }
}
