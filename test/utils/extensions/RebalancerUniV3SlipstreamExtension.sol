/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ArcadiaLogic } from "../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { IPool } from "../../../src/rebalancers/interfaces/IPool.sol";
import { IUniswapV3Pool } from "../../../src/rebalancers/interfaces/IUniswapV3Pool.sol";
import { PricingLogic } from "../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalanceLogic } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { UniswapV3Logic } from "../../../src/rebalancers/libraries/uniswap-v3/UniswapV3Logic.sol";
import { RebalancerUniV3Slipstream } from "../../../src/rebalancers/RebalancerUniV3Slipstream.sol";

contract RebalancerUniV3SlipstreamExtension is RebalancerUniV3Slipstream {
    using SafeTransferLib for ERC20;

    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio)
        RebalancerUniV3Slipstream(maxTolerance, maxInitiatorFee, minLiquidityRatio)
    { }

    function getRebalanceParams(
        RebalancerUniV3Slipstream.PositionState memory position,
        uint256 amount0,
        uint256 amount1,
        uint256 initiatorFee
    )
        public
        view
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic._getRebalanceParams(
            RebalancerUniV3Slipstream.MIN_LIQUIDITY_RATIO,
            position.fee,
            initiatorFee,
            position.sqrtPriceX96,
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            amount0,
            amount1
        );
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
            revert RebalancerUniV3Slipstream.UnbalancedPool();
        }
    }

    function encodeAction(
        address positionManager,
        uint256 id,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) public pure returns (bytes memory actionData) {
        actionData = ArcadiaLogic._encodeAction(positionManager, id, initiator, tickLower, tickUpper, swapData);
    }

    function setAccount(address account_) public {
        account = account_;
    }

    function setHook(address account_, address hook) public {
        strategyHook[account_] = hook;
    }
}
