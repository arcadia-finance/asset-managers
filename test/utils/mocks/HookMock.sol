/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PositionState } from "../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { StrategyHook } from "../../../src/cl-managers/rebalancers/periphery/StrategyHook.sol";

contract HookMock is StrategyHook {
    function setStrategy(address account, bytes calldata strategyData) external override { }
    function beforeRebalance(
        address account,
        address positionManager,
        PositionState memory position,
        bytes memory strategyData
    ) external view override returns (int24 tickLower, int24 tickUpper) { }
    function afterRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        PositionState memory newPosition,
        bytes memory strategyData
    ) external override { }
}
