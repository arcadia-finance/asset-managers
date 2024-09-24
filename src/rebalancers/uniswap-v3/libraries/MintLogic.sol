/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { ERC20, SafeTransferLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ICLPositionManager } from "../interfaces/ICLPositionManager.sol";
import { IUniswapV3PositionManager } from "../interfaces/IUniswapV3PositionManager.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { UniswapV3Logic } from "./UniswapV3Logic.sol";
import { UniswapV3Rebalancer } from "../UniswapV3Rebalancer.sol";

library MintLogic {
    using SafeTransferLib for ERC20;

    function _mint(
        address positionManager,
        UniswapV3Rebalancer.PositionState memory position,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 newTokenId, uint256 liquidity, uint256 balance0_, uint256 balance1_) {
        // The approval for at least one token after increasing liquidity will remain non-zero.
        // We have to set approval first to 0 for ERC20 tokens that require the approval to be set to zero
        // before setting it to a non-zero value.
        // ToDo: use Solady library that handles revert on non-zero approval.
        ERC20(position.token0).safeApprove(positionManager, 0);
        ERC20(position.token0).safeApprove(positionManager, balance0);
        ERC20(position.token1).safeApprove(positionManager, 0);
        ERC20(position.token1).safeApprove(positionManager, balance1);

        uint256 amount0;
        uint256 amount1;
        (newTokenId, liquidity, amount0, amount1) = (positionManager == address(SlipstreamLogic.POSITION_MANAGER))
            ? SlipstreamLogic.POSITION_MANAGER.mint(
                ICLPositionManager.MintParams({
                    token0: position.token0,
                    token1: position.token1,
                    tickSpacing: position.tickSpacing,
                    tickLower: position.lowerTick,
                    tickUpper: position.upperTick,
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp,
                    sqrtPriceX96: uint160(position.sqrtPriceX96)
                })
            )
            : UniswapV3Logic.POSITION_MANAGER.mint(
                IUniswapV3PositionManager.MintParams({
                    token0: position.token0,
                    token1: position.token1,
                    fee: position.fee,
                    tickLower: position.lowerTick,
                    tickUpper: position.upperTick,
                    amount0Desired: balance0,
                    amount1Desired: balance1,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );

        // Update balances.
        balance0_ = balance0 - amount0;
        balance1_ = balance1 - amount1;
    }
}
