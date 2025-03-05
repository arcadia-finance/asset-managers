/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Currency } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeApprove } from "./SafeApprove.sol";
import { ICLPositionManager } from "../interfaces/ICLPositionManager.sol";
import { IHooks } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";
import { IUniswapV3PositionManager } from "../interfaces/IUniswapV3PositionManager.sol";
import { LiquidityAmounts } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { Rebalancer } from "../Rebalancer.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { StakedSlipstreamLogic } from "./StakedSlipstreamLogic.sol";
import { UniswapV3Logic } from "./UniswapV3Logic.sol";
import { UniswapV4Logic } from "./UniswapV4Logic.sol";

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

        uint256 amount0;
        uint256 amount1;
        if (positionManager == address(UniswapV4Logic.POSITION_MANAGER)) {
            uint256 ethValue =
                (position.token0 == address(0) ? balance0 : 0) + (position.token1 == address(0) ? balance1 : 0);
            // Manage token approvals and check if native ETH has to be added to the position.
            if (position.token0 != address(0)) UniswapV4Logic._checkAndApprovePermit2(position.token0, balance0);
            if (position.token1 != address(0)) UniswapV4Logic._checkAndApprovePermit2(position.token1, balance1);

            // Generate calldata to mint new position.
            bytes memory actions = new bytes(2);
            actions[0] = bytes1(uint8(UniswapV4Logic.MINT_POSITION));
            actions[1] = bytes1(uint8(UniswapV4Logic.SETTLE_PAIR));

            PoolKey memory poolKey = PoolKey(
                Currency.wrap(position.token0),
                Currency.wrap(position.token1),
                position.fee,
                position.tickSpacing,
                IHooks(position.pool)
            );

            (uint160 newSqrtPriceX96,,,) = UniswapV4Logic.STATE_VIEW.getSlot0(poolKey.toId());
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                newSqrtPriceX96, position.sqrtRatioLower, position.sqrtRatioUpper, balance0, balance1
            );

            bytes[] memory params = new bytes[](2);
            params[0] = abi.encode(
                poolKey,
                position.tickLower,
                position.tickUpper,
                liquidity,
                type(uint128).max,
                type(uint128).max,
                address(this),
                ""
            );
            params[1] = abi.encode(poolKey.currency0, poolKey.currency1);

            // Get new token id.
            newTokenId = UniswapV4Logic.POSITION_MANAGER.nextTokenId();

            bytes memory mintParams = abi.encode(actions, params);
            UniswapV4Logic.POSITION_MANAGER.modifyLiquidities{ value: ethValue }(mintParams, block.timestamp);
        } else {
            // Manage token approvals.
            ERC20(position.token0).safeApproveWithRetry(positionManager, balance0);
            ERC20(position.token1).safeApproveWithRetry(positionManager, balance1);

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
        }

        // If position is a staked slipstream position, stake the position.
        if (stakedPositionManager != address(0)) {
            SlipstreamLogic.POSITION_MANAGER.approve(stakedPositionManager, newTokenId);
            IStakedSlipstreamAM(stakedPositionManager).mint(newTokenId);
        }
    }
}
