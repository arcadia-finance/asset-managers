/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { ERC20, SafeApprove } from "../../../libraries/SafeApprove.sol";
import { IHooks } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IHooks.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { RebalanceOptimizationMath } from "../RebalanceOptimizationMath.sol";
import { RebalancerUniswapV4 } from "../../RebalancerUniswapV4.sol";
import { SwapParams } from "../../interfaces/IPoolManager.sol";
import { UniswapV4Logic } from "../uniswap-v4/UniswapV4Logic.sol";

library SwapLogicV4 {
    using SafeApprove for ERC20;

    /**
     * @notice Swaps one token for another to rebalance the Liquidity Position.
     * @param swapData Arbitrary calldata provided by an initiator for the swap.
     * @param position Struct with the position data.
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
        bytes memory swapData,
        RebalancerUniswapV4.PositionState memory position,
        PoolKey memory poolKey,
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
                UniswapV4Logic.STATE_VIEW.getLiquidity(poolKey.toId()),
                uint160(position.sqrtPriceX96),
                position.sqrtRatioLower,
                position.sqrtRatioUpper,
                zeroToOne ? balance0 - amountInitiatorFee : balance0,
                zeroToOne ? balance1 : balance1 - amountInitiatorFee,
                amountIn,
                amountOut
            );
            // Don't do swaps with zero amount.
            if (amountOut == 0) return (balance0, balance1);
            (balance0_, balance1_) = _swapViaPool(poolKey, position, zeroToOne, amountOut, balance0, balance1);
        } else {
            (balance0_, balance1_) = _swapViaRouter(poolKey, position, zeroToOne, swapData);
        }
    }

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param poolKey The struct identifying the Uniswap V4 pool.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @param balance0 The balance of token0 before the swap.
     * @param balance1 The balance of token1 before the swap.
     * @return balance0_ The balance of token0 after the swap.
     * @return balance1_ The balance of token1 after the swap.
     */
    function _swapViaPool(
        PoolKey memory poolKey,
        RebalancerUniswapV4.PositionState memory position,
        bool zeroToOne,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 balance0_, uint256 balance1_) {
        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Encode the swap data.
        SwapParams memory params = SwapParams({
            zeroForOne: zeroToOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        bytes memory swapData = abi.encode(params, poolKey);

        // Do the swap.
        bytes memory results = UniswapV4Logic.POOL_MANAGER.unlock(swapData);
        BalanceDelta swapDelta = abi.decode(results, (BalanceDelta));

        int256 deltaAmount0 = swapDelta.amount0();
        int256 deltaAmount1 = swapDelta.amount1();

        // Check that pool is still balanced.
        // If sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received, the pool is not balanced anymore.
        // By setting the sqrtPriceX96 to sqrtPriceLimitX96, the transaction will revert on the balance check.
        if (amountOut > (zeroToOne ? uint256(deltaAmount1) : uint256(deltaAmount0))) {
            position.sqrtPriceX96 = sqrtPriceLimitX96;
        }

        // Update the balances.
        balance0_ = zeroToOne ? balance0 - uint256(-deltaAmount0) : balance0 + uint256(deltaAmount0);
        balance1_ = zeroToOne ? balance1 + uint256(deltaAmount1) : balance1 - uint256(-deltaAmount1);
    }

    /**
     * @notice Swaps one token for another, directly through the pool itself.
     * @param poolKey The struct identifying the Uniswap V4 pool.
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
        PoolKey memory poolKey,
        RebalancerUniswapV4.PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal returns (uint256 balance0, uint256 balance1) {
        // Decode the swap data.
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

        // Approve token to swap.
        address tokenToSwap = zeroToOne ? position.token0 : position.token1;
        uint256 ethValue;
        if (tokenToSwap == address(0)) {
            ethValue = amountIn;
        } else {
            ERC20(tokenToSwap).safeApproveWithRetry(router, amountIn);
        }

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call{ value: ethValue }(data);
        require(success, string(result));

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        // Since the swap went potentially through the pool itself (but does not have to),
        // the sqrtPriceX96 might have moved and brought the pool out of balance.
        // By fetching the sqrtPriceX96, the transaction will revert in that case on the balance check.
        (position.sqrtPriceX96,,,) = UniswapV4Logic.STATE_VIEW.getSlot0(poolKey.toId());

        // Update the balances.
        balance0 =
            position.token0 == address(0) ? address(this).balance : ERC20(position.token0).balanceOf(address(this));
        balance1 =
            position.token1 == address(0) ? address(this).balance : ERC20(position.token1).balanceOf(address(this));
    }
}
