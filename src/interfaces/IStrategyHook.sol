/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { PositionState } from "../state/PositionState.sol";

interface IStrategyHook {
    function beforeRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        int24 newTickLower,
        int24 newTickUpper
    ) external view;
    function beforeRebalance(
        address account,
        address positionManager,
        PositionState memory position,
        bytes memory strategyData
    ) external view returns (int24 tickLower, int24 tickUpper);

    function afterRebalance(address account, address positionManager, uint256 oldId, uint256 newId) external;
    function afterRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        PositionState memory position,
        bytes memory strategyData
    ) external;

    function setRebalanceInfo(address account, address token0, address token1, bytes calldata rebalanceInfo) external;
    function setStrategy(address account, bytes calldata strategyData) external;
}
