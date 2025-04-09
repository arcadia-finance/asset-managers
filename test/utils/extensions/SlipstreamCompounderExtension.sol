/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounder } from "../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamLogic } from "../../../src/compounders/slipstream/libraries/SlipstreamLogic.sol";

contract SlipstreamCompounderExtension is SlipstreamCompounder {
    constructor(uint256 maxTolerance, uint256 maxInitiatorShare)
        SlipstreamCompounder(maxTolerance, maxInitiatorShare)
    { }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return SlipstreamLogic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swap(PositionState memory position, bool zeroToOne, uint256 amountOut) public returns (bool) {
        return _swap(position, zeroToOne, amountOut);
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
