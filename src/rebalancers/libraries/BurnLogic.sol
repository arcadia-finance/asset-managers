/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { CollectParams, DecreaseLiquidityParams, IPositionManager } from "../interfaces/IPositionManager.sol";
import { Rebalancer } from "../Rebalancer.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./StakedSlipstreamLogic.sol";

library BurnLogic {
    /**
     * @notice Burns the Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @param position Struct with the position data.
     * @return balance0 The amount of token0 claimed.
     * @return balance1 The amount of token1 claimed.
     * @return rewards The amount of reward token claimed.
     */
    function _burn(address positionManager, uint256 id, Rebalancer.PositionState memory position)
        internal
        returns (uint256 balance0, uint256 balance1, uint256 rewards)
    {
        // If position is a staked slipstream position, first unstake the position.
        if (positionManager == address(StakedSlipstreamLogic.POSITION_MANAGER)) {
            // Staking rewards are deposited back into the account at the end of the transaction.
            // Or, if rewardToken is an underlying token of the position, added to the balances
            rewards = StakedSlipstreamLogic.POSITION_MANAGER.burn(id);

            // After position is unstaked, it becomes a slipstream position.
            positionManager = address(SlipstreamLogic.POSITION_MANAGER);
        }

        // Remove liquidity of the position and claim outstanding fees to get full amounts of token0 and token1
        // for rebalance.
        IPositionManager(positionManager).decreaseLiquidity(
            DecreaseLiquidityParams({
                tokenId: id,
                liquidity: position.liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        // We assume that the amount of tokens to collect never exceeds type(uint128).max.
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

        if (positionManager == address(StakedSlipstreamLogic.POSITION_MANAGER)) {
            if (position.tokenR == position.token0) (balance0, rewards) = (balance0 + rewards, 0);
            else if (position.tokenR == position.token1) (balance1, rewards) = (balance1 + rewards, 0);
        }
    }
}
