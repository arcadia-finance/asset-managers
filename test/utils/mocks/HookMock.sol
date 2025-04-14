/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

contract HookMock {
    mapping(address account => bytes rebalanceInfo) public rebalanceInfo;

    function beforeRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        int24 newTickLower,
        int24 newTickUpper
    ) external view { }

    function afterRebalance(address account, address positionManager, uint256 oldId, uint256 newId) external { }

    function setRebalanceInfo(address account, bytes calldata rebalanceInfo_) external {
        rebalanceInfo[account] = rebalanceInfo_;
    }
}
