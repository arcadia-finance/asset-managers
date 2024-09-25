/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ICLPool } from "../interfaces/ICLPool.sol";
import { IPool } from "../interfaces/IPool.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3Pool.sol";
import { SlipstreamLogic } from "./SlipstreamLogic.sol";
import { SwapMath } from "./SwapMath.sol";
import { Rebalancer } from "../Rebalancer.sol";

library SwapLogic {
    using SafeTransferLib for ERC20;

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
        (balance0_, balance1_) = swapData.length == 0
            ? _swapViaPool(
                positionManager, position, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
            )
            : _swapViaRouter(positionManager, position, zeroToOne, swapData);
    }

    /**
     * @notice Swaps one token to the other token in the Uniswap V3 Pool of the Liquidity Position.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     */
    function _swapViaPool(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        uint256 amountIn,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256 balance0_, uint256 balance1_) {
        // Calculate the exact amountOut, with slippage that will be swapped.
        amountOut = SwapMath.getAmountOutWithSlippage(
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

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Do the swap.
        // Callback (external function) must be implemented in the main contract.
        bytes memory data = (positionManager == address(SlipstreamLogic.POSITION_MANAGER))
            ? abi.encode(positionManager, position.token0, position.token1, position.tickSpacing)
            : abi.encode(positionManager, position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IPool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        if (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0))) {
            position.sqrtPriceX96 = sqrtPriceLimitX96;
        }

        // Update the balances.
        balance0_ = zeroToOne ? balance0 - uint256(deltaAmount0) : balance0 + uint256(-deltaAmount0);
        balance1_ = zeroToOne ? balance1 + uint256(-deltaAmount1) : balance1 - uint256(deltaAmount1);
    }

    /**
     * @notice Allows an initiator to perform an arbitrary swap.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param swapData A bytes object containing a contract address and another bytes object with the calldata to send to that address.
     * @dev In order for such a swap to be valid, the amountOut should be at least equal to the amountOut expected if the swap
     * occured in the pool of the position itself. The amountIn should also fully have been utilized, to keep target ratio valid.
     */
    function _swapViaRouter(
        address positionManager,
        Rebalancer.PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) internal returns (uint256 balance0, uint256 balance1) {
        (address router, uint256 amountIn, bytes memory data) = abi.decode(swapData, (address, uint256, bytes));

        // Approve token to swap.
        address tokenToSwap = zeroToOne ? position.token0 : position.token1;
        ERC20(tokenToSwap).safeApprove(router, 0);
        ERC20(tokenToSwap).safeApprove(router, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = router.call(data);
        require(success, string(result));

        // Pool should still be balanced.
        if (positionManager == address(SlipstreamLogic.POSITION_MANAGER)) {
            (position.sqrtPriceX96,,,,,) = ICLPool(position.pool).slot0();
        } else {
            (position.sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
        }

        // Update the balances.
        balance0 = ERC20(position.token0).balanceOf(address(this));
        balance1 = ERC20(position.token1).balanceOf(address(this));
    }
}
