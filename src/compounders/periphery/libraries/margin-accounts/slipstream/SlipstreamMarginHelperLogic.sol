/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Fees, ISlipstreamCompounder, PositionState } from "../../../../slipstream/interfaces/ISlipstreamCompounder.sol";
import { FixedPoint128 } from
    "../../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { ICLPool } from "../../../../slipstream/interfaces/ICLPool.sol";
import { IQuoter, QuoteExactOutputSingleParams } from "../../../../slipstream/interfaces/IQuoter.sol";
import { LiquidityAmounts } from "../../../../libraries/LiquidityAmounts.sol";
import { TickMath } from "../../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { SlipstreamLogic } from "../../../../slipstream/libraries/SlipstreamLogic.sol";

/**
 * @title Off-chain view functions for Slipstream Compounder Asset-Manager.
 * @author Pragma Labs
 * @notice This library holds view functions accessible for initiators to check if the fees of a certain Liquidity Position can be compounded.
 */
library SlipstreamMarginHelperLogic {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                            CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Asset Manager.
    ISlipstreamCompounder internal constant COMPOUNDER =
        ISlipstreamCompounder(payable((0xccc601cFd309894ED7B8F15Cb35057E5A6a18B79)));

    // The Slipstream Quoter contract.
    IQuoter internal constant QUOTER = IQuoter(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0);

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @return usdValueFees The total value of the fees in USD, with 18 decimals precision.
     * @return compounder_ The address of the Compounder contract.
     * @dev While this function does not persist state changes, it cannot be declared as view function.
     * Since quoteExactOutputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id)
        public
        returns (bool isCompoundable_, uint256 usdValueFees, address compounder_)
    {
        // Fetch and cache all position related data.
        PositionState memory position = COMPOUNDER.getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (COMPOUNDER.isPoolUnbalanced(position)) return (false, 0, address(0));

        // Get fee amounts
        Fees memory balances;
        (balances.amount0, balances.amount1) = _getFeeAmounts(id);

        // Total value of the fees must be greater than the threshold.
        usdValueFees = position.usdPriceToken0.mulDivDown(balances.amount0, 1e18)
            + position.usdPriceToken1.mulDivDown(balances.amount1, 1e18);
        if (usdValueFees < COMPOUNDER.COMPOUND_THRESHOLD()) return (false, 0, address(0));

        // Remove initiator reward from fees, these will be send to the initiator.
        Fees memory desiredAmounts;
        uint256 initiatorShare = COMPOUNDER.INITIATOR_SHARE();
        desiredAmounts.amount0 = balances.amount0 - balances.amount0.mulDivDown(initiatorShare, 1e18);
        desiredAmounts.amount1 = balances.amount1 - balances.amount1.mulDivDown(initiatorShare, 1e18);

        // Calculate fee amounts to match ratios of current pool tick relative to ticks of the position.
        (bool zeroToOne, uint256 amountOut) = COMPOUNDER.getSwapParameters(position, desiredAmounts);
        (bool isPoolUnbalanced, uint256 amountIn) = _quote(position, zeroToOne, amountOut);

        // Pool should still be balanced after the swap.
        if (isPoolUnbalanced) return (false, 0, address(0));

        // Calculate balances after swap.
        // Note that for the desiredAmounts only tokenOut is updated in SlipstreamCompounder,
        // but not tokenIn.
        if (zeroToOne) {
            desiredAmounts.amount1 += amountOut;
            balances.amount0 -= amountIn;
            balances.amount1 += amountOut;
        } else {
            desiredAmounts.amount0 += amountOut;
            balances.amount0 += amountOut;
            balances.amount1 -= amountIn;
        }

        // The balances of the fees after swapping must be bigger than the actual input amount when increasing liquidity.
        // Due to slippage, or for pools with high swapping fees this might not always hold.
        (uint256 amount0, uint256 amount1) = _getLiquidityAmounts(position, desiredAmounts);
        return (balances.amount0 > amount0 && balances.amount1 > amount1, usdValueFees, address(COMPOUNDER));
    }

    /**
     * @notice Off-chain view function to get the quote of a swap.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount of tokenOut that must be swapped to.
     * @return isPoolUnbalanced Bool indicating if the pool is unbalanced due to slippage after the swap.
     * @return amountIn The amount of tokenIn that is swapped to tokenOut.
     * @dev While this function does not persist state changes, it cannot be declared as view function,
     * since quoteExactOutputSingle() of Slipstream's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function _quote(PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        returns (bool isPoolUnbalanced, uint256 amountIn)
    {
        // Don't get quote for swaps with zero amount.
        if (amountOut == 0) return (false, 0);

        // Max slippage: Pool should still be balanced after the swap.
        uint256 sqrtPriceLimitX96 = zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96;

        // Quote the swap.
        uint160 sqrtPriceX96After;
        (amountIn, sqrtPriceX96After,,) = QUOTER.quoteExactOutputSingle(
            QuoteExactOutputSingleParams({
                tokenIn: zeroToOne ? position.token0 : position.token1,
                tokenOut: zeroToOne ? position.token1 : position.token0,
                amount: amountOut,
                tickSpacing: position.tickSpacing,
                sqrtPriceLimitX96: uint160(sqrtPriceLimitX96)
            })
        );

        // Check if max slippage was exceeded (sqrtPriceLimitX96 is reached).
        isPoolUnbalanced = sqrtPriceX96After == sqrtPriceLimitX96 ? true : false;

        // Update the sqrtPriceX96 of the pool.
        position.sqrtPriceX96 = sqrtPriceX96After;
    }

    /**
     * @notice Calculates the underlying token amounts of accrued fees, both collected and uncollected.
     * @param id The id of the Liquidity Position.
     * @return amount0 The amount of fees in underlying token0 tokens.
     * @return amount1 The amount of fees in underlying token1 tokens.
     */
    function _getFeeAmounts(uint256 id) internal view returns (uint256 amount0, uint256 amount1) {
        (
            ,
            ,
            address token0,
            address token1,
            int24 tickSpacing,
            int24 tickLower,
            int24 tickUpper,
            uint256 liquidity, // gas: cheaper to use uint256 instead of uint128.
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0, // gas: cheaper to use uint256 instead of uint128.
            uint256 tokensOwed1 // gas: cheaper to use uint256 instead of uint128.
        ) = SlipstreamLogic.POSITION_MANAGER.positions(id);

        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            _getFeeGrowthInside(token0, token1, tickSpacing, tickLower, tickUpper);

        // Calculate the total amount of fees by adding the already realized fees (tokensOwed),
        // to the accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in NonfungiblePositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 = FullMath.mulDiv(
                feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed0;
            amount1 = FullMath.mulDiv(
                feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed1;
        }
    }

    /**
     * @notice Calculates the current fee growth inside the Liquidity Range.
     * @param token0 Token0 of the Liquidity Pool.
     * @param token1 Token1 of the Liquidity Pool.
     * @param tickSpacing The tickSpacing of the Liquidity Pool.
     * @param tickLower The lower tick of the liquidity position.
     * @param tickUpper The upper tick of the liquidity position.
     * @return feeGrowthInside0X128 The amount of fees in underlying token0 tokens.
     * @return feeGrowthInside1X128 The amount of fees in underlying token1 tokens.
     */
    function _getFeeGrowthInside(address token0, address token1, int24 tickSpacing, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        ICLPool pool = ICLPool(SlipstreamLogic._computePoolAddress(token0, token1, tickSpacing));

        // To calculate the pending fees, the current tick has to be used, even if the pool would be unbalanced.
        (, int24 tickCurrent,,,,) = pool.slot0();
        (,,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,,) = pool.ticks(tickLower);
        (,,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,,) = pool.ticks(tickUpper);

        // Calculate the fee growth inside of the Liquidity Range since the last time the position was updated.
        // feeGrowthInside can overflow (without reverting), as is the case in the Slipstream fee calculations.
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                feeGrowthInside0X128 =
                    pool.feeGrowthGlobal0X128() - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    pool.feeGrowthGlobal1X128() - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
    }

    /**
     * @notice returns the actual amounts of token0 and token1 when increasing liquidity,
     * for a given position and desired amount of tokens.
     * @param position Struct with the position data.
     * @param amountsDesired Struct with the desired amounts of tokens supplied.
     * @return amount0 The actual amount of token0 supplied.
     * @return amount1 The actual amount of token1 supplied.
     */
    function _getLiquidityAmounts(PositionState memory position, Fees memory amountsDesired)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(position.sqrtPriceX96),
            uint160(position.sqrtRatioLower),
            uint160(position.sqrtRatioUpper),
            amountsDesired.amount0,
            amountsDesired.amount1
        );
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPriceX96),
            uint160(position.sqrtRatioLower),
            uint160(position.sqrtRatioUpper),
            liquidity
        );
    }
}
