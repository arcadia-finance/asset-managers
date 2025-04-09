/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { MintLogic } from "../../../src/rebalancers/libraries/MintLogic.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";

contract MintLogicExtension {
    function mint(address positionManager, Rebalancer.PositionState memory position, uint256 balance0, uint256 balance1)
        external
        returns (uint256 newTokenId, uint256 liquidity, uint256 balance0_, uint256 balance1_)
    {
        return MintLogic._mint(positionManager, position, balance0, balance1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
