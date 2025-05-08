/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceLogic, RebalanceParams } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";

contract RebalanceLogicExtension {
    function getRebalanceParams(
        uint256 maxSlippageRatio,
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1
    ) external pure returns (RebalanceParams memory) {
        return RebalanceLogic._getRebalanceParams(
            maxSlippageRatio, poolFee, initiatorFee, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1
        );
    }
}
