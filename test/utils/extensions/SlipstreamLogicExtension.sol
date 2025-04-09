/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalancerUniV3Slipstream } from "../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { SlipstreamLogic } from "../../../src/rebalancers/libraries/slipstream/SlipstreamLogic.sol";

contract SlipstreamLogicExtension {
    function computePoolAddress(address token0, address token1, int24 tickSpacing)
        external
        pure
        returns (address pool)
    {
        pool = SlipstreamLogic._computePoolAddress(token0, token1, tickSpacing);
    }

    function getPositionState(RebalancerUniV3Slipstream.PositionState memory position, uint256 id)
        external
        view
        returns (int24 tickCurrent, int24 tickRange, RebalancerUniV3Slipstream.PositionState memory position_)
    {
        (tickCurrent, tickRange) = SlipstreamLogic._getPositionState(position, id);
        position_ = position;
    }
}
