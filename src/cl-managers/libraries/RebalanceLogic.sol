/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "./LiquidityAmounts.sol";
import { CLMath } from "./CLMath.sol";

struct RebalanceParams {
    // Bool indicating if token0 has to be swapped to token1 or opposite.
    bool zeroToOne;
    // The amount of initiator fee, in tokenIn.
    uint256 amountInitiatorFee;
    // The minimum amount of liquidity that must be added to the position.
    uint256 minLiquidity;
    // An approximation of the amount of tokenIn, based on the optimal swap through the pool itself without slippage.
    uint256 amountIn;
    // An approximation of the amount of tokenOut, based on the optimal swap through the pool itself without slippage.
    uint256 amountOut;
}

library RebalanceLogic {
    using FixedPointMathLib for uint256;

    /**
     * @notice Returns the parameters and constraints to rebalance the position.
     * Both parameters and constraints are calculated based on a hypothetical swap (in the pool itself with fees but without slippage),
     * that maximizes the amount of liquidity that can be added to the positions (no leftovers of either token0 or token1).
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param poolFee The fee of the pool, with 6 decimals precision.
     * @param initiatorFee The fee of the initiator, with 18 decimals precision.
     * @param sqrtPrice The square root of the price (token1/token0), with 96 binary precision.
     * @param sqrtRatioLower The square root price of the lower tick of the liquidity position, with 96 binary precision.
     * @param sqrtRatioUpper The square root price of the upper tick of the liquidity position, with 96 binary precision.
     * @param balance0 The amount of token0 that is available for the rebalance.
     * @param balance1 The amount of token1 that is available for the rebalance.
     * @return rebalanceParams A struct with the rebalance parameters.
     */
    function _getRebalanceParams(
        uint256 minLiquidityRatio,
        uint256 poolFee,
        uint256 initiatorFee,
        uint256 sqrtPrice,
        uint256 sqrtRatioLower,
        uint256 sqrtRatioUpper,
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (RebalanceParams memory rebalanceParams) {
        // Total fee is pool fee + initiator fee, with 18 decimals precision.
        // Since Uniswap uses 6 decimals precision for the fee, we have to multiply the pool fee by 1e12.
        uint256 fee;
        unchecked {
            fee = initiatorFee + poolFee * 1e12;
        }

        // Calculate the swap parameters
        (bool zeroToOne, uint256 amountIn, uint256 amountOut) =
            CLMath._getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Calculate the maximum amount of liquidity that can be added to the position.
        uint256 minLiquidity;
        {
            // forge-lint: disable-next-item(unsafe-typecast)
            uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                uint160(sqrtPrice),
                uint160(sqrtRatioLower),
                uint160(sqrtRatioUpper),
                zeroToOne ? balance0 - amountIn : balance0 + amountOut,
                zeroToOne ? balance1 + amountOut : balance1 - amountIn
            );
            minLiquidity = liquidity.mulDivDown(minLiquidityRatio, 1e18);
        }

        // Get initiator fee amount and the actual amountIn of the swap (without initiator fee).
        uint256 amountInitiatorFee;
        unchecked {
            amountInitiatorFee = amountIn.mulDivDown(initiatorFee, 1e18);
            amountIn = amountIn - amountInitiatorFee;
        }

        rebalanceParams = RebalanceParams({
            zeroToOne: zeroToOne,
            amountInitiatorFee: amountInitiatorFee,
            minLiquidity: minLiquidity,
            amountIn: amountIn,
            amountOut: amountOut
        });
    }
}
