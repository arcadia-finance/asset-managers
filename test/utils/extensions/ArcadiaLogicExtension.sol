/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ArcadiaLogic } from "../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";

contract ArcadiaLogicExtension {
    function encodeDeposit(
        address positionManager,
        uint256 id,
        Rebalancer.PositionState memory position,
        uint256 count,
        uint256 balance0,
        uint256 balance1,
        uint256 reward
    ) external pure returns (ActionData memory depositData) {
        depositData = ArcadiaLogic._encodeDeposit(positionManager, id, position, count, balance0, balance1, reward);
    }
}
