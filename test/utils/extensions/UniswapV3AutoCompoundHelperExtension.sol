/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { IUniswapV3AutoCompounder } from
    "../../../src/auto-compounders/uniswap-v3/interfaces/IUniswapV3AutoCompounder.sol";
import { PositionState } from "../../../src/auto-compounders/uniswap-v3/interfaces/IUniswapV3AutoCompounder.sol";
import { UniswapV3AutoCompoundHelper } from
    "../../../src/auto-compounders/uniswap-v3/periphery/UniswapV3AutoCompoundHelper.sol";
import { UniswapV3Logic } from "../../../src/auto-compounders/uniswap-v3/libraries/UniswapV3Logic.sol";

contract UniswapV3AutoCompoundHelperExtension is UniswapV3AutoCompoundHelper {
    constructor(address autoCompounder_) UniswapV3AutoCompoundHelper(autoCompounder_) { }

    function quote(PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced)
    {
        isPoolUnbalanced = _quote(position, zeroToOne, amountOut);
    }
}
