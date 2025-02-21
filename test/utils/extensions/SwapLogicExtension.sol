/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";
import { SlipstreamLogic } from "../../../src/rebalancers/libraries/SlipstreamLogic.sol";
import { SwapLogic } from "../../../src/rebalancers/libraries/SwapLogic.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/libraries/UniswapV3Logic.sol";

contract SwapLogicExtension {
    using SafeTransferLib for ERC20;

    function swap(
        bytes memory swapData,
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        uint256 amountIn,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) external returns (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) {
        (balance0_, balance1_) = SwapLogic._swap(
            swapData, positionManager, position, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
        );

        position_ = position;
    }

    function swapViaPool(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) external returns (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) {
        (balance0_, balance1_) =
            SwapLogic._swapViaPool(positionManager, position, zeroToOne, amountOut, balance0, balance1);

        position_ = position;
    }

    function swapViaRouter(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) external returns (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) {
        (balance0_, balance1_) = SwapLogic._swapViaRouter(positionManager, position, zeroToOne, swapData);

        position_ = position;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // Check that callback came from an actual Uniswap V3 or Slipstream pool.
        (address positionManager, address token0, address token1, uint24 feeOrTickSpacing) =
            abi.decode(data, (address, address, address, uint24));
        if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
            if (UniswapV3Logic._computePoolAddress(token0, token1, feeOrTickSpacing) != msg.sender) {
                revert Rebalancer.OnlyPool();
            }
        } else {
            // Logic holds for both Slipstream and staked Slipstream positions.
            if (SlipstreamLogic._computePoolAddress(token0, token1, int24(feeOrTickSpacing)) != msg.sender) {
                revert Rebalancer.OnlyPool();
            }
        }

        if (amount0Delta > 0) {
            ERC20(token0).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            ERC20(token1).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }
}
