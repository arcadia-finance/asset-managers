/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

contract HookMock {
    // A mapping from an Arcadia Account to a struct with Account-specific rebalancing information.
    mapping(address account => RebalanceInfo) public rebalanceInfo;

    // A struct containing Account-specific rebalancing information.
    struct RebalanceInfo {
        address token0;
        address token1;
        bytes customInfo;
    }

    function beforeRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        int24 newTickLower,
        int24 newTickUpper
    ) external view { }

    function afterRebalance(address account, address positionManager, uint256 oldId, uint256 newId) external { }

    function setRebalanceInfo(address account, address token0_, address token1_, bytes calldata customInfo) external {
        rebalanceInfo[account] = RebalanceInfo({ token0: token0_, token1: token1_, customInfo: customInfo });
    }
}
