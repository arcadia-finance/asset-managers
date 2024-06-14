/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ISlipstreamAutoCompounder } from
    "../../../src/auto-compounders/slipstream/interfaces/ISlipstreamAutoCompounder.sol";
import { PositionState } from "../../../src/auto-compounders/slipstream/interfaces/ISlipstreamAutoCompounder.sol";
import { SlipstreamAutoCompoundHelper } from
    "../../../src/auto-compounders/slipstream/periphery/SlipstreamAutoCompoundHelper.sol";
import { SlipstreamLogic } from "../../../src/auto-compounders/slipstream/libraries/SlipstreamLogic.sol";

contract SlipstreamAutoCompoundHelperExtension is SlipstreamAutoCompoundHelper {
    constructor(address autoCompounder_) SlipstreamAutoCompoundHelper(autoCompounder_) { }

    function quote(PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced)
    {
        isPoolUnbalanced = _quote(position, zeroToOne, amountOut);
    }
}
