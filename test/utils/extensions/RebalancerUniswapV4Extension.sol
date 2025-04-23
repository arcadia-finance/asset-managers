/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ArcadiaLogic } from "../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PricingLogic } from "../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalanceLogic } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalancerUniswapV4 } from "../../../src/rebalancers/RebalancerUniswapV4.sol";
import { UniswapV4Logic } from "../../../src/rebalancers/libraries/uniswap-v4/UniswapV4Logic.sol";
import { SwapLogicV4 } from "../../../src/rebalancers/libraries/uniswap-v4/SwapLogicV4.sol";

contract RebalancerUniswapV4Extension is RebalancerUniswapV4 {
    using SafeTransferLib for ERC20;

    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio)
        RebalancerUniswapV4(maxTolerance, maxInitiatorFee, minLiquidityRatio)
    { }

    function getRebalanceParams(PositionState memory position, uint256 amount0, uint256 amount1, uint256 initiatorFee)
        public
        view
        returns (uint256 minLiquidity, bool zeroToOne, uint256 amountInitiatorFee, uint256 amountIn, uint256 amountOut)
    {
        return RebalanceLogic._getRebalanceParams(
            RebalancerUniswapV4.MIN_LIQUIDITY_RATIO,
            position.fee,
            initiatorFee,
            position.sqrtPriceX96,
            position.sqrtRatioLower,
            position.sqrtRatioUpper,
            amount0,
            amount1
        );
    }

    function encodeAction(
        address positionManager,
        uint256 id,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        uint256 trustedSqrtPriceX96,
        bytes calldata swapData
    ) public pure returns (bytes memory actionData) {
        actionData = ArcadiaLogic._encodeAction(
            positionManager, id, initiator, tickLower, tickUpper, trustedSqrtPriceX96, swapData
        );
    }

    function setHook(address account, address hook) public {
        strategyHook[account] = hook;
    }

    function swap(
        bytes memory swapData,
        RebalancerUniswapV4.PositionState memory position,
        PoolKey memory poolKey,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        uint256 amountIn,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) public returns (uint256 balance0_, uint256 balance1_, RebalancerUniswapV4.PositionState memory position_) {
        (balance0_, balance1_) = SwapLogicV4._swap(
            swapData, position, poolKey, zeroToOne, amountInitiatorFee, amountIn, amountOut, balance0, balance1
        );
        position_ = position;
    }

    function swapViaPool(
        PoolKey memory poolKey,
        RebalancerUniswapV4.PositionState memory position,
        bool zeroToOne,
        uint256 amountOut,
        uint256 balance0,
        uint256 balance1
    ) public returns (uint256 balance0_, uint256 balance1_, RebalancerUniswapV4.PositionState memory position_) {
        (balance0_, balance1_) = SwapLogicV4._swapViaPool(poolKey, position, zeroToOne, amountOut, balance0, balance1);
        position_ = position;
    }

    function swapViaRouter(
        PoolKey memory poolKey,
        RebalancerUniswapV4.PositionState memory position,
        bool zeroToOne,
        bytes memory swapData
    ) public returns (uint256 balance0, uint256 balance1, RebalancerUniswapV4.PositionState memory position_) {
        (balance0, balance1) = SwapLogicV4._swapViaRouter(poolKey, position, zeroToOne, swapData);
        position_ = position;
    }

    function mint(
        RebalancerUniswapV4.PositionState memory position,
        PoolKey memory poolKey,
        uint256 amount0,
        uint256 amount1
    ) public returns (uint256 newTokenId, uint256 liquidity) {
        (newTokenId, liquidity) = _mint(position, poolKey, amount0, amount1);
    }

    function burn(uint256 id, address token0, address token1) public {
        _burn(id, token0, token1);
    }

    function setAccount(address account_) public {
        account = account_;
    }
}
