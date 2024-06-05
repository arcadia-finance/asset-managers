/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { IAutoCompounder } from "../../../src/auto-compounder/interfaces/IAutoCompounder.sol";
import { AutoCompounderViews } from "../../../src/auto-compounder/AutoCompounderViews.sol";
import { UniswapV3Logic } from "../../../src/auto-compounder/libraries/UniswapV3Logic.sol";

contract AutoCompounderViewsExtension is AutoCompounderViews {
    constructor(address autoCompounder_) AutoCompounderViews(autoCompounder_) { }

    function quote(IAutoCompounder.PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced)
    {
        isPoolUnbalanced = _quote(position, zeroToOne, amountOut);
    }
}
