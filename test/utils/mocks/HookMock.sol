/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

contract HookMock {
    function afterRebalance(address positionManager, uint256 oldId, uint256 newId) external { }
}
