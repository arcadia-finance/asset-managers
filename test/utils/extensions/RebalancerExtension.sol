/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PositionState } from "../../../src/state/PositionState.sol";
import { RebalanceParams } from "../../../src/libraries/RebalanceLogic.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";

contract RebalancerExtension is Rebalancer {
    constructor(address arcadiaFactory, uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio)
        Rebalancer(arcadiaFactory, maxTolerance, maxInitiatorFee, minLiquidityRatio)
    { }

    function isPositionManager(address positionManager) public view override returns (bool) { }

    function _getUnderlyingTokens(address positionManager, uint256 id)
        internal
        view
        override
        returns (address token0, address token1)
    { }

    function _getPositionState(address positionManager, uint256 id)
        internal
        view
        override
        returns (PositionState memory)
    { }

    function _getPoolLiquidity(PositionState memory position) internal view override returns (uint128) { }

    function _getSqrtPrice(PositionState memory position) internal view override returns (uint160) { }

    function _claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) internal override { }

    function _unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    function _burn(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    function _swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        override
    { }

    function swapViaRouter(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) external returns (uint256[] memory balances_) {
        _swapViaRouter(balances, position, zeroToOne, swapData);
        balances_ = balances;
    }

    function _mint(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal override { }

    function _increaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal override { }

    function _stake(uint256[] memory balances, address positionManager, PositionState memory position)
        internal
        override
    { }

    function approveAndTransfer(
        address initiator,
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position
    ) external returns (uint256[] memory balances_, uint256 count) {
        count = _approveAndTransfer(initiator, balances, fees, positionManager, position);
        balances_ = balances;
    }

    function setHook(address account_, address hook) public {
        strategyHook[account_] = hook;
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
