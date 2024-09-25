/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IPool } from "../../../src/rebalancers/uniswap-v3/interfaces/IPool.sol";
import { IUniswapV3Pool } from "../../../src/rebalancers/uniswap-v3/interfaces/IUniswapV3Pool.sol";
import { PricingLogic } from "../../../src/rebalancers/uniswap-v3/libraries/PricingLogic.sol";
import { RebalanceLogic } from "../../../src/rebalancers/uniswap-v3/libraries/RebalanceLogic.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/uniswap-v3/libraries/UniswapV3Logic.sol";
import { Rebalancer } from "../../../src/rebalancers/uniswap-v3/Rebalancer.sol";

contract RebalancerExtension is Rebalancer {
    using SafeTransferLib for ERC20;

    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio)
        Rebalancer(maxTolerance, maxInitiatorFee, maxSlippageRatio)
    { }

    function getRebalanceParams(
        uint256 maxSlippageRatio,
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    )
        public
        pure
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic.getRebalanceParams(
            maxSlippageRatio, poolFee, initiatorFee, sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1
        );
    }

    function getRebalanceParams(
        Rebalancer.PositionState memory position,
        uint256 amount0,
        uint256 amount1,
        uint256 initiatorFee
    )
        public
        view
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic.getRebalanceParams(
            Rebalancer.MAX_SLIPPAGE_RATIO,
            position.fee,
            initiatorFee,
            position.sqrtPriceX96,
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            amount0,
            amount1
        );
    }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint256) {
        return PricingLogic._getSqrtPriceX96(priceToken0, priceToken1);
    }

    function swapViaPool(PositionState memory position, bool zeroToOne, uint256 amountOut)
        public
        returns (bool isPoolUnbalanced_)
    {
        // Don't do swaps with zero amount.
        if (amountOut == 0) return false;

        // Pool should still be balanced (within tolerance boundaries) after the swap.
        uint160 sqrtPriceLimitX96 =
            uint160(zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96);

        // Do the swap.
        bytes memory data =
            abi.encode(address(UniswapV3Logic.POSITION_MANAGER), position.token0, position.token1, position.fee);
        (int256 deltaAmount0, int256 deltaAmount1) =
            IPool(position.pool).swap(address(this), zeroToOne, -int256(amountOut), sqrtPriceLimitX96, data);

        // Check if pool is still balanced (sqrtPriceLimitX96 is reached before an amountOut of tokenOut is received).
        isPoolUnbalanced_ = (amountOut > (zeroToOne ? uint256(-deltaAmount1) : uint256(-deltaAmount0)));
    }

    function swapViaRouter(PositionState memory position, bool zeroToOne, uint256 amountIn, bytes memory swapData)
        external
    {
        (address to, bytes memory data) = abi.decode(swapData, (address, bytes));

        // Approve token to swap.
        address tokenToSwap = zeroToOne ? position.token0 : position.token1;
        ERC20(tokenToSwap).safeApprove(to, 0);
        ERC20(tokenToSwap).safeApprove(to, amountIn);

        // Execute arbitrary swap.
        (bool success, bytes memory result) = to.call(data);
        require(success, string(result));

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();
        // Uniswap V3 pool should still be balanced.
        if (sqrtPriceX96 < position.lowerBoundSqrtPriceX96 || sqrtPriceX96 > position.upperBoundSqrtPriceX96) {
            revert Rebalancer.UnbalancedPool();
        }
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
