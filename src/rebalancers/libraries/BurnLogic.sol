/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CollectParams, DecreaseLiquidityParams, IPositionManager } from "../interfaces/IPositionManager.sol";
import { Currency } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";
import { Rebalancer } from "../Rebalancer.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./StakedSlipstreamLogic.sol";
import { UniswapV4Logic } from "./UniswapV4Logic.sol";

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
        if (positionManager == address(UniswapV4Logic.POSITION_MANAGER)) {
            (balance0, balance1) = _burnUniswapV4Logic(id, position.token0, position.token1);
        } else {
            (balance0, balance1, rewards) = _burnUniswapV3Logic(positionManager, id, position);
        }
    }

    /**
     * @notice Burns the Liquidity Position for Uniswap V3 type positions.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @param position Struct with the position data.
     * @return balance0 The amount of token0 claimed.
     * @return balance1 The amount of token1 claimed.
     * @return rewards The amount of reward token claimed.
     */
    function _burnUniswapV3Logic(address positionManager, uint256 id, Rebalancer.PositionState memory position)
        internal
        returns (uint256 balance0, uint256 balance1, uint256 rewards)
    {
        // If position is a staked slipstream position, first unstake the position.
        bool staked;
        if (
            positionManager == address(StakedSlipstreamLogic.STAKED_SLIPSTREAM_AM)
                || positionManager == address(StakedSlipstreamLogic.STAKED_SLIPSTREAM_WRAPPER)
        ) {
            // Staking rewards are deposited back into the account at the end of the transaction.
            // Or, if rewardToken is an underlying token of the position, added to the balances
            rewards = IStakedSlipstreamAM(positionManager).burn(id);
            // After the position is unstaked, it becomes a slipstream position.
            positionManager = address(SlipstreamLogic.POSITION_MANAGER);
            staked = true;
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

        // If the reward token is the same as one of the underlying tokens, update the token-balance instead.
        if (staked) {
            if (StakedSlipstreamLogic.REWARD_TOKEN == position.token0) {
                (balance0, rewards) = (balance0 + rewards, 0);
            } else if (StakedSlipstreamLogic.REWARD_TOKEN == position.token1) {
                (balance1, rewards) = (balance1 + rewards, 0);
            }
        }
    }

    /**
     * @notice Burns the Liquidity Position for Uniswap V4 type positions.
     * @param id The id of the Liquidity Position.
     * @param token0 The address of token0 of the liquidity position.
     * @param token1 The address of token1 of the liquidity position.
     * @return balance0 The amount of token0 claimed.
     * @return balance1 The amount of token1 claimed.
     */
    function _burnUniswapV4Logic(uint256 id, address token0, address token1)
        internal
        returns (uint256 balance0, uint256 balance1)
    {
        // Generate calldata to collect fees (decrease liquidity with liquidityDelta = 0).
        bytes memory actions = new bytes(2);
        actions[0] = bytes1(uint8(UniswapV4Logic.BURN_POSITION));
        actions[1] = bytes1(uint8(UniswapV4Logic.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        Currency currency0 = Currency.wrap(token0);
        Currency currency1 = Currency.wrap(token1);
        params[0] = abi.encode(id, 0, 0, "");
        params[1] = abi.encode(currency0, currency1, address(this));

        // Cache init balance of token0 and token1.
        uint256 initBalanceCurrency0 = currency0.balanceOfSelf();
        uint256 initBalanceCurrency1 = currency1.balanceOfSelf();

        bytes memory burnParams = abi.encode(actions, params);
        UniswapV4Logic.POSITION_MANAGER.modifyLiquidities(burnParams, block.timestamp);

        balance0 = currency0.balanceOfSelf() - initBalanceCurrency0;
        balance1 = currency1.balanceOfSelf() - initBalanceCurrency1;
    }
}
