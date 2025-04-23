/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { BurnLogic } from "../../../src/rebalancers/libraries/shared-uniswap-v3-slipstream/BurnLogic.sol";
import { RebalancerUniV3Slipstream } from "../../../src/rebalancers/RebalancerUniV3Slipstream.sol";

contract BurnLogicExtension {
    function burn(address positionManager, uint256 id, RebalancerUniV3Slipstream.PositionState memory position)
        external
        returns (uint256 balance0, uint256 balance1, uint256 rewards)
    {
        return BurnLogic._burn(positionManager, id, position);
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
