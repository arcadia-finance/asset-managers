/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FeeLogic } from "../../../src/rebalancers/libraries/FeeLogic.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";

contract FeeLogicExtension {
    function transfer(
        address initiator,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1
    ) external returns (uint256, uint256) {
        return FeeLogic._transfer(initiator, zeroToOne, amountInitiatorFee, token0, token1, balance0, balance1);
    }
}
