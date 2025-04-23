/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { MintLogic } from "../../../src/rebalancers/libraries/shared-uniswap-v3-slipstream/MintLogic.sol";
import { RebalancerUniV3Slipstream } from "../../../src/rebalancers/RebalancerUniV3Slipstream.sol";

contract MintLogicExtension {
    function mint(
        address positionManager,
        RebalancerUniV3Slipstream.PositionState memory position,
        uint256 balance0,
        uint256 balance1
    ) external returns (uint256 newTokenId, uint256 liquidity, uint256 balance0_, uint256 balance1_) {
        return MintLogic._mint(positionManager, position, balance0, balance1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
