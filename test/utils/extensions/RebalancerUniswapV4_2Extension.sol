/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceParams } from "../../../src/rebalancers/libraries/RebalanceLogic2.sol";
import { RebalancerUniswapV4 } from "../../../src/rebalancers/RebalancerUniswapV4_2.sol";

contract RebalancerUniswapV4Extension is RebalancerUniswapV4 {
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address permit2,
        address poolManager,
        address weth
    )
        RebalancerUniswapV4(
            arcadiaFactory,
            maxTolerance,
            maxInitiatorFee,
            minLiquidityRatio,
            positionManager,
            permit2,
            poolManager,
            weth
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

    function getSqrtPriceX96(PositionState memory position) external view returns (uint160) {
        return _getSqrtPriceX96(position);
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
        RebalanceParams memory rebalanceParams,
        Cache memory cache,
        uint256 amountOut
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _swapViaPool(balances, position, rebalanceParams, cache, amountOut);
        balances_ = balances;
        position_ = position;
    }

    function swapViaRouter(
        uint256[] memory balances,
        PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _swapViaRouter(balances, position, zeroToOne, swapData);
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
