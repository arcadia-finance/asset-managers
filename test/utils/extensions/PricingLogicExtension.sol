/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PricingLogic } from "../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";

contract PricingLogicExtension {
    function getSpotValue(uint256 sqrtPriceX96, bool zeroToOne, uint256 amountIn)
        external
        pure
        returns (uint256 amountOut)
    {
        return PricingLogic._getSpotValue(sqrtPriceX96, zeroToOne, amountIn);
    }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) external pure returns (uint256) {
        return PricingLogic._getSqrtPriceX96(priceToken0, priceToken1);
    }
}
