/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ISlipstreamCompounder } from "../../../src/compounders/slipstream/interfaces/ISlipstreamCompounder.sol";
import { PositionState } from "../../../src/compounders/slipstream/interfaces/ISlipstreamCompounder.sol";
import { SlipstreamCompounderHelper } from
    "../../../src/compounders/periphery/libraries/margin-accounts/slipstream/SlipstreamCompounderHelper.sol";
import { SlipstreamLogic } from "../../../src/compounders/slipstream/libraries/SlipstreamLogic.sol";

contract SlipstreamCompounderHelperExtension is SlipstreamCompounderHelper {
    constructor(address compounder_) SlipstreamCompounderHelper(compounder_) { }

    function quote(PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced, uint256 amountIn)
    {
        return _quote(position, zeroToOne, amountOut);
    }
}
