/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

interface IStrategyHook {
    function beforeRebalance(address positionManager, uint256 oldId, int24 newTickLower, int24 newTickUpper)
        external
        view;

    function afterRebalance(address positionManager, uint256 oldId, uint256 newId) external;
}
