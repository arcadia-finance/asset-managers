/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { CollectParams, DecreaseLiquidityParams, IPositionManager } from "../interfaces/IPositionManager.sol";
import { Rebalancer } from "../Rebalancer.sol";

library BurnLogic {
    function _burn(address positionManager, uint256 id, uint128 liquidity)
        internal
        returns (uint256 balance0, uint256 balance1)
    {
        // Remove liquidity of the position and claim outstanding fees to get full amounts of token0 and token1
        // for rebalance.
        IPositionManager(positionManager).decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: id,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        (balance0, balance1) = IPositionManager(positionManager).collect(
            CollectParams({
                tokenId: id,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        // Burn the position
        IPositionManager(positionManager).burn(id);
    }
}
