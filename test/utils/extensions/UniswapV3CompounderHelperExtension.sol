/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { IUniswapV3Compounder } from "../../../src/compounders/uniswap-v3/interfaces/IUniswapV3Compounder.sol";
import { PositionState } from "../../../src/compounders/uniswap-v3/interfaces/IUniswapV3Compounder.sol";
import { UniswapV3CompounderHelper } from "../../../src/compounders/uniswap-v3/periphery/UniswapV3CompounderHelper.sol";
import { UniswapV3Logic } from "../../../src/compounders/uniswap-v3/libraries/UniswapV3Logic.sol";

contract UniswapV3CompounderHelperExtension is UniswapV3CompounderHelper {
    constructor(address compounder_) UniswapV3CompounderHelper(compounder_) { }

    function quote(PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced)
    {
        isPoolUnbalanced = _quote(position, zeroToOne, amountOut);
    }
}
