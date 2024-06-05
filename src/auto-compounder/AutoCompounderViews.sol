/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder } from "./AutoCompounder.sol";
import { IAutoCompounder } from "./interfaces/IAutoCompounder.sol";
import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { QuoteExactOutputSingleParams } from "./interfaces/IQuoter.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";

/**
 * @title Off-chain view functions for UniswapV3 AutoCompounder Asset-Manager.
 * @author Pragma Labs
 * @notice This contract holds view functions accessible for initiators to check if the fees of a certain Liquidity Position can be compounded.
 */
contract AutoCompounderViews {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                            CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The contract address of the Asset Manager.
    AutoCompounder public immutable autoCompounder;

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param autoCompounder_ The contract address of the Asset-Manager for compounding UniswapV3 fees of a certain Liquidity Position.
     */
    constructor(address autoCompounder_) {
        autoCompounder = AutoCompounder(autoCompounder_);
    }

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @dev While this function does not persist state changes, it cannot be declared as view function.
     * Since quoteExactInputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id) external returns (bool isCompoundable_) {
        // Fetch and cache all position related data.
        AutoCompounder.PositionState memory position = autoCompounder.getPositionState(id);

        // Check that pool is initially balanced.
        // Prevents sandwiching attacks when swapping and/or adding liquidity.
        if (autoCompounder.isPoolUnbalanced(position)) return false;

        // Get fee amounts
        AutoCompounder.Fees memory fees;
        (fees.amount0, fees.amount1) = UniswapV3Logic._getFeeAmounts(id);

        // Total value of the fees must be greater than the threshold.
        if (autoCompounder.isBelowThreshold(position, fees)) return false;

        // Remove initiator reward from fees, these will be send to the initiator.
        uint256 initiatorShare = autoCompounder.INITIATOR_SHARE();
        fees.amount0 -= fees.amount0.mulDivDown(initiatorShare, 1e18);
        fees.amount1 -= fees.amount1.mulDivDown(initiatorShare, 1e18);

        // Calculate fee amounts to match ratios of current pool tick relative to ticks of the position.
        // Pool should still be balanced after the swap.
        (bool zeroToOne, uint256 amountOut) = autoCompounder.getSwapParameters(position, fees);
        bool isPoolUnbalanced = _quote(position, zeroToOne, amountOut);

        isCompoundable_ = !isPoolUnbalanced;
    }

    /**
     * @notice Off-chain view function to get the quote of a swap.
     * @param position Struct with the position data.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountOut The amount that of tokenOut that must be swapped to.
     * @return isPoolUnbalanced Bool indicating if the pool is unbalanced due to slippage after the swap.
     * @dev While this function does not persist state changes, it cannot be declared as view function,
     * since quoteExactInputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function _quote(AutoCompounder.PositionState memory position, bool zeroToOne, uint256 amountOut)
        internal
        returns (bool isPoolUnbalanced)
    {
        // Don't get quote for swaps with zero amount.
        if (amountOut == 0) return false;

        // Max slippage: Pool should still be balanced after the swap.
        uint256 sqrtPriceLimitX96 = zeroToOne ? position.lowerBoundSqrtPriceX96 : position.upperBoundSqrtPriceX96;

        // Quote the swap.
        (, uint160 sqrtPriceX96After,,) = UniswapV3Logic.QUOTER.quoteExactOutputSingle(
            QuoteExactOutputSingleParams({
                tokenIn: zeroToOne ? position.token0 : position.token1,
                tokenOut: zeroToOne ? position.token1 : position.token0,
                amountOut: amountOut,
                fee: position.fee,
                sqrtPriceLimitX96: uint160(sqrtPriceLimitX96)
            })
        );

        // Check if max slippage was exceeded (sqrtPriceLimitX96 is reached).
        isPoolUnbalanced = sqrtPriceX96After == sqrtPriceLimitX96 ? true : false;
    }
}