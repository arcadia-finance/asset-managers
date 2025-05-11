/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalanceParams } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalancerUniswapV3 } from "../../../src/rebalancers/RebalancerUniswapV3.sol";

contract RebalancerUniswapV3Extension is RebalancerUniswapV3 {
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address uniswapV3Factory
    )
        RebalancerUniswapV3(
            arcadiaFactory,
            maxTolerance,
            maxInitiatorFee,
            minLiquidityRatio,
            positionManager,
            uniswapV3Factory
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

    function mint(uint256[] memory balances, address positionManager, PositionState memory position)
        external
        returns (uint256[] memory balances_, PositionState memory position_)
    {
        _mint(balances, positionManager, position);
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
