/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { PositionState } from "../../../src/state/PositionState.sol";
import { RebalanceParams } from "../../../src/libraries/RebalanceLogic.sol";
import { RebalancerUniswapV4 } from "../../../src/rebalancers/RebalancerUniswapV4.sol";

contract RebalancerUniswapV4Extension is RebalancerUniswapV4 {
    constructor(
        address arcadiaFactory,
        uint256 maxFee,
        uint256 maxTolerance,
        uint256 minLiquidityRatio,
        address positionManager,
        address permit2,
        address poolManager,
        address weth
    )
        RebalancerUniswapV4(
            arcadiaFactory,
            maxFee,
            maxTolerance,
            minLiquidityRatio,
            positionManager,
            permit2,
            poolManager,
            weth
        )
    { }

    function getUnderlyingTokens(address positionManager, uint256 id) external view returns (address, address) {
        return _getUnderlyingTokens(positionManager, id);
    }

    function getPositionState(address positionManager, uint256 id) external view returns (PositionState memory) {
        return _getPositionState(positionManager, id);
    }

    function getPoolLiquidity(PositionState memory position) external view returns (uint128) {
        return _getPoolLiquidity(position);
    }

    function getSqrtPrice(PositionState memory position) external view returns (uint160) {
        return _getSqrtPrice(position);
    }

    function claim(
        uint256[] memory balances,
        uint256[] memory fees,
        address positionManager,
        PositionState memory position,
        uint256 claimFee
    ) external returns (uint256[] memory balances_, uint256[] memory fees_) {
        _claim(balances, fees, positionManager, position, claimFee);
        balances_ = balances;
        fees_ = fees;
    }

    function unstake(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_)
    {
        _unstake(balances, positionManager, position);
        balances_ = balances;
    }

    function burn(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_)
    {
        _burn(balances, positionManager, position);
        balances_ = balances;
    }

    function swapViaPool(uint256[] memory balances, PositionState memory position, bool zeroToOne, uint256 amountOut)
        external
        returns (uint256[] memory balances_, PositionState memory position_)
    {
        _swapViaPool(balances, position, zeroToOne, amountOut);
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
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _mint(balances, positionManager, position, amount0Desired, amount1Desired);
        balances_ = balances;
        position_ = position;
    }

    function increaseLiquidity(
        uint256[] memory balances,
        address positionManager,
        PositionState memory position,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external returns (uint256[] memory balances_, PositionState memory position_) {
        _increaseLiquidity(balances, positionManager, position, amount0Desired, amount1Desired);
        balances_ = balances;
        position_ = position;
    }

    function stake(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_, PositionState memory position_)
    {
        _stake(balances, positionManager, position);
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
