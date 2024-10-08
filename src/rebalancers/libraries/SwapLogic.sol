/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20, SafeApprove } from "./SafeApprove.sol";
import { ICLPool } from "../interfaces/ICLPool.sol";
import { IPool } from "../interfaces/IPool.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { Rebalancer } from "../Rebalancer.sol";
import { RebalanceOptimizationMath } from "./RebalanceOptimizationMath.sol";
import { UniswapV3Logic } from "./UniswapV3Logic.sol";

library SwapLogic {
    using SafeApprove for ERC20;

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param position Struct with the position data.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountInitiatorFee The amount of initiator fee, in tokenIn.
     * @param amountIn An approximation of the amount of tokenIn, based on the optimal swap through the pool itself without slippage.
     * @param amountOut An approximation of the amount of tokenOut, based on the optimal swap through the pool itself without slippage.
     * @param balance0 The balance of token0 before the swap.
     * @param balance1 The balance of token1 before the swap.
     * @return balance0_ The balance of token0 after the swap.
     * @return balance1_ The balance of token1 after the swap.
     */
    function _swap(
        address positionManager,
        Rebalancer.PositionState memory position,
        bytes memory swapData,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        uint256 amountIn,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 balance0_, uint256 balance1_) {
        // Don't do swaps with zero amount.
        if (amountIn == 0) return (balance0, balance1);

        // Do the actual swap to rebalance the position.
        // This can be done either directly through the pool, or via a router with custom swap data.
        if (swapData.length == 0) {
            // Calculate a more accurate amountOut, with slippage.
            amountOut = RebalanceOptimizationMath._getAmountOutWithSlippage(
                zeroToOne,
                position.fee,
                IPool(position.pool).liquidity(),
                uint160(position.sqrtPriceX96),
                position.sqrtRatioLower,
                position.sqrtRatioUpper,
                zeroToOne ? balance0 - amountInitiatorFee : balance0,
                zeroToOne ? balance1 : balance1 - amountInitiatorFee,
                amountIn,
                amountOut
            );
            (balance0_, balance1_) = _swapViaPool(positionManager, position, zeroToOne, amountOut, balance0, balance1);
        } else {
            (balance0_, balance1_) = _swapViaRouter(positionManager, position, zeroToOne, swapData);
        }
    }

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param positionManager The contract address of the Position Manager.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @param balance0 The balance of token0 before the swap.
     * @param balance1 The balance of token1 before the swap.
     * @return balance0_ The balance of token0 after the swap.
     * @return balance1_ The balance of token1 after the swap.
     */
    function _swapViaPool(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 balance0_, uint256 balance1_) {
        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Encode the swap data.
        bytes memory data = (positionManager == address(UniswapV3Logic.POSITION_MANAGER))
            ? abi.encode(positionManager, position.token0, position.token1, position.fee)
            // Logic holds for both Slipstream and staked Slipstream positions.
            : abi.encode(positionManager, position.token0, position.token1, position.tickSpacing);

        // Do the swap.
        // Callback (external function) must be implemented in the main contract.
        (int256 deltaAmount0, int256 deltaAmount1) =
            IPool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check that pool is still balanced.
        // If sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received, the pool is not balanced anymore.
        // By setting the sqrtPriceX96 to sqrtPriceLimitX96, the transaction will revert on the balance check.
        if (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0))) {
            position.sqrtPriceX96 = sqrtPriceLimitX96;
        }

        // Update the balances.
        balance0_ = zeroToOne ? balance0 - uint256(deltaAmount0) : balance0 + uint256(-deltaAmount0);
        balance1_ = zeroToOne ? balance1 + uint256(-deltaAmount1) : balance1 - uint256(deltaAmount1);
    }

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param positionManager The contract address of the Position Manager.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @return balance0 The balance of token0 after the swap.
     * @return balance1 The balance of token1 after the swap.
     * @dev Initiator has to route swap in such a way that at least minLiquidity of liquidity is added to the position after the swap.
     * And leftovers must be in tokenIn, otherwise the total tokenIn balance will be added as liquidity,
     * and the initiator fee will be 0 (but the transaction will not revert)
     */
    function _swapViaRouter(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal returns (uint256 balance0, uint256 balance1) {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

        // Approve token to swap.
        address tokenToSwap = zeroToOne ? position.token0 : position.token1;
        ERC20(tokenToSwap).safeApproveWithRetry(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPriceX96 might have moved and brought the pool out of balance.
        // By fetching the sqrtPriceX96, the transaction will revert in that case on the balance check.
        if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
            (position.sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
        } else {
            // Logic holds for both Slipstream and staked Slipstream positions.
            (position.sqrtPriceX96,,,,,) = ICLPool(position.pool).slot0();
        }

        // Update the balances.
        balance0 = ERC20(position.token0).balanceOf(address(this));
        balance1 = ERC20(position.token1).balanceOf(address(this));
    }
}
