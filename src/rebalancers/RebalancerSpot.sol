/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Rebalancer } from "./Rebalancer.sol";
import { SlipstreamLogic } from "./libraries/SlipstreamLogic.sol";
import { TickMath } from "../../lib/accounts-v2/lib/v4-periphery-fork/lib/v4-core/src/libraries/TickMath.sol";
import { TwapLogic } from "../libraries/TwapLogic.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";

/**
 * @title Permissioned rebalancer for Uniswap V3 and Slipstream Liquidity Positions.
 * @notice The Rebalancer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permisionned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The contract prevents frontrunning/sandwiching by comparing the actual pool price with a pool price calculated from a TWAP.
 * The tolerance in terms of price deviation is specific to the initiator but limited by a global MAX_TOLERANCE.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
contract RebalancerSpot is Rebalancer {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxInitiatorFee The maximum fee an initiator can set,
     * relative to the ideal amountIn, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     */
    constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 minLiquidityRatio)
        Rebalancer(maxTolerance, maxInitiatorFee, minLiquidityRatio)
    { }

    /* ///////////////////////////////////////////////////////////////
                    PUBLIC POSITION VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param positionManager The contract address of the Position Manager.
     * @param oldId The oldId of the Liquidity Position.
     * @param tickLower The lower tick of the newly minted position.
     * @param tickUpper The upper tick of the newly minted position.
     * @param initiator The address of the initiator.
     * @return position Struct with the position data.
     */
    function getPositionState(
        address positionManager,
        uint256 oldId,
        int24 tickLower,
        int24 tickUpper,
        address initiator
    ) public view override returns (PositionState memory position) {
        // Get data of the Liquidity Position.
        (int24 tickCurrent, int24 tickRange) = positionManager == address(UniswapV3Logic.POSITION_MANAGER)
            ? UniswapV3Logic._getPositionState(position, oldId, tickLower == tickUpper)
            // Logic holds for both Slipstream and staked Slipstream positions.
            : SlipstreamLogic._getPositionState(position, oldId);

        // Store the new ticks for the rebalance
        if (tickLower == tickUpper) {
            // Round current tick down to a tick that is a multiple of the tick spacing (can be initialised).
            // We do not handle the edge cases where the new ticks might exceed MIN_TICK or MAX_TICK.
            // This will result in a revert during the mint, if ever needed a different rebalancer has to be deployed.
            tickCurrent = tickCurrent / position.tickSpacing * position.tickSpacing;
            // For tick ranges that are an even multiple of the tick spacing, we use a symmetric spacing around the current tick.
            // For uneven multiples, the smaller part is below the current tick.
            position.tickLower = tickCurrent - tickRange / (2 * position.tickSpacing) * position.tickSpacing;
            position.tickUpper = position.tickLower + tickRange;
        } else {
            (position.tickLower, position.tickUpper) = (tickLower, tickUpper);
        }
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // Calculate the time weighted average tick over 300s.
        // It is used only to ensure that the deposited Liquidity range and thus
        // the risk of exposure manipulation is acceptable.
        int24 twat = TwapLogic._getTwat(position.pool);
        // Get the time weighted average sqrtPriceX96 over 300s.
        uint256 twaSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twat);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be in acceptable balanced state.
        // We do not handle the edge cases where exceed MIN_SQRT_RATIO or MAX_SQRT_RATIO.
        // This will result in a revert during swapViaPool, if ever needed a different rebalancer has to be deployed.
        position.lowerBoundSqrtPriceX96 =
            twaSqrtPriceX96.mulDivDown(initiatorInfo[initiator].lowerSqrtPriceDeviation, 1e18);
        position.upperBoundSqrtPriceX96 =
            twaSqrtPriceX96.mulDivDown(initiatorInfo[initiator].upperSqrtPriceDeviation, 1e18);
    }
}
