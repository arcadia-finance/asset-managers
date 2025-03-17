/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ArcadiaLogic } from "../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { PricingLogic } from "../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalanceLogic } from "../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { UniswapV4Logic } from "../../../src/rebalancers/libraries/uniswap-v4/UniswapV4Logic.sol";
import { RebalancerUniswapV4 } from "../../../src/rebalancers/RebalancerUniswapV4.sol";

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
        bytes calldata swapData
    ) public pure returns (bytes memory actionData) {
        actionData = ArcadiaLogic._encodeAction(positionManager, id, initiator, tickLower, tickUpper, swapData);
    }

    function setHook(address account, address hook) public {
        strategyHook[account] = hook;
    }

    function setTransientStorage(address account, uint256 sqrtPriceX96) public {
        assembly {
            tstore(ACCOUNT_SLOT, account)
            tstore(TRUSTED_SQRT_PRICE_X96_SLOT, sqrtPriceX96)
        }
    }
}
