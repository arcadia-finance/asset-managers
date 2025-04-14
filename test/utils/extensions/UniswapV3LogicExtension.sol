/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/libraries/UniswapV3Logic.sol";

contract UniswapV3LogicExtension {
    function computePoolAddress(address token0, address token1, uint24 fee) external pure returns (address pool) {
        pool = UniswapV3Logic._computePoolAddress(token0, token1, fee);
    }

    function getPositionState(Rebalancer.PositionState memory position, uint256 id, bool getTickSpacing)
        external
        view
        returns (int24 tickCurrent, int24 tickRange, Rebalancer.PositionState memory position_)
    {
        (tickCurrent, tickRange) = UniswapV3Logic._getPositionState(position, id, getTickSpacing);
        position_ = position;
    }
}
