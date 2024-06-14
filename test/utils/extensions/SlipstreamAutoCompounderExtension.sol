/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamAutoCompounder } from "../../../src/auto-compounders/slipstream/SlipstreamAutoCompounder.sol";
import { SlipstreamLogic } from "../../../src/auto-compounders/slipstream/libraries/SlipstreamLogic.sol";

contract SlipstreamAutoCompounderExtension is SlipstreamAutoCompounder {
    constructor(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance)
        SlipstreamAutoCompounder(compoundThreshold, initiatorShare, tolerance)
    { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return SlipstreamLogic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }
}
