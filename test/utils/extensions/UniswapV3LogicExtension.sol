/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalancerUniV3Slipstream } from "../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/libraries/uniswap-v3/UniswapV3Logic.sol";

contract UniswapV3LogicExtension {
    function computePoolAddress(address token0, address token1, uint24 fee) external pure returns (address pool) {
        pool = UniswapV3Logic._computePoolAddress(token0, token1, fee);
    }

    function getPositionState(RebalancerUniV3Slipstream.PositionState memory position, uint256 id, bool getTickSpacing)
        external
        view
        returns (int24 tickCurrent, int24 tickRange, RebalancerUniV3Slipstream.PositionState memory position_)
    {
        (tickCurrent, tickRange) = UniswapV3Logic._getPositionState(position, id, getTickSpacing);
        position_ = position;
    }
}
