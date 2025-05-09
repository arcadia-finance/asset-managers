/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceParams } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalancerSlipstream } from "../../../src/rebalancers/RebalancerSlipstream.sol";

contract RebalancerSlipstreamExtension is RebalancerSlipstream {
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    )
        RebalancerSlipstream(
            arcadiaFactory,
            maxTolerance,
            maxInitiatorFee,
            minLiquidityRatio,
            positionManager,
            cLFactory,
            poolImplementation,
            rewardToken,
            stakedSlipstreamAm,
            stakedSlipstreamWrapper
        )
    { }

    function getUnderlyingTokens(InitiatorParams memory initiatorParams) external view returns (address, address) {
        return _getUnderlyingTokens(initiatorParams);
    }

    function getPositionState(InitiatorParams memory initiatorParams)
        external
        view
        returns (uint256[] memory, PositionState memory)
    {
        return _getPositionState(initiatorParams);
    }

    function getPoolLiquidity(PositionState memory position) external view returns (uint128) {
        return _getPoolLiquidity(position);
    }

    function getSqrtPrice(PositionState memory position) external view returns (uint160) {
        return _getSqrtPrice(position);
    }

    function burn(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) external returns (uint256[] memory balances_) {
        _burn(balances, initiatorParams, position, cache);
        balances_ = balances;
    }

    function swapViaPool(
        uint256[] memory balances,
        PositionState memory position,
        Cache memory cache,
        bool zeroToOne,
        uint256 amountOut
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _swapViaPool(balances, position, cache, zeroToOne, amountOut);
        balances_ = balances;
        position_ = position;
    }

    function mint(
        uint256[] memory balances,
        InitiatorParams memory initiatorParams,
        PositionState memory position,
        Cache memory cache
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _mint(balances, initiatorParams, position, cache);
        balances_ = balances;
        position_ = position;
    }

    function setHook(address account_, address hook) public {
        strategyHook[account_] = hook;
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
