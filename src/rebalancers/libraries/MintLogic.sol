/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, SafeApprove } from "./SafeApprove.sol";
import { ICLPositionManager } from "../interfaces/ICLPositionManager.sol";
import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";
import { IUniswapV3PositionManager } from "../interfaces/IUniswapV3PositionManager.sol";
import { Rebalancer } from "../Rebalancer.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./StakedSlipstreamLogic.sol";
import { UniswapV3Logic } from "./UniswapV3Logic.sol";

library MintLogic {
    using SafeApprove for ERC20;

    /**
     * @notice Mints a new Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param position Struct with the position data.
     * @param balance0 The balance of token0 before minting liquidity.
     * @param balance1 The balance of token1 before minting liquidity.
     * @return newTokenId The id of the new Liquidity Position.
     * @return liquidity The amount of liquidity minted.
     * @return balance0_ The remaining balance of token0 after minting liquidity.
     * @return balance1_ The remaining balance of token1 after minting liquidity.
     */
    function _mint(
        address positionManager,
        Rebalancer.PositionState memory position,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 newTokenId, uint256 liquidity, uint256 balance0_, uint256 balance1_) {
        // Before position can be staked, we have to create a slipstream position.
        address stakedPositionManager;
        if (
            positionManager == StakedSlipstreamLogic.STAKED_SLIPSTREAM_AM
                || positionManager == StakedSlipstreamLogic.STAKED_SLIPSTREAM_WRAPPER
        ) {
            stakedPositionManager = positionManager;
            positionManager = address(SlipstreamLogic.POSITION_MANAGER);
        }

        ERC20(position.token0).safeApproveWithRetry(positionManager, balance0);
        ERC20(position.token1).safeApproveWithRetry(positionManager, balance1);

        uint256 amount0;
        uint256 amount1;
        (newTokenId, liquidity, amount0, amount1) = (positionManager == address(UniswapV3Logic.POSITION_MANAGER))
            ? UniswapV3Logic.POSITION_MANAGER.mint(
                IUniswapV3PositionManager.MintParams({
                    token0: position.token0,
                    token1: position.token1,
                    fee: position.fee,
                    tickLower: position.tickLower,
                    tickUpper: position.tickUpper,
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            )
            : SlipstreamLogic.POSITION_MANAGER.mint(
                ICLPositionManager.MintParams({
                    token0: position.token0,
                    token1: position.token1,
                    tickSpacing: position.tickSpacing,
                    tickLower: position.tickLower,
                    tickUpper: position.tickUpper,
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp,
                    sqrtPriceX96: 0
                })
            );

        // Update balances.
        balance0_ = balance0 - amount0;
        balance1_ = balance1 - amount1;

        // If position is a staked slipstream position, stake the position.
        if (stakedPositionManager != address(0)) {
            SlipstreamLogic.POSITION_MANAGER.approve(stakedPositionManager, newTokenId);
            IStakedSlipstreamAM(stakedPositionManager).mint(newTokenId);
        }
    }
}
