/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { PositionState } from "../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";
import { StrategyHook } from "../../../src/rebalancers/periphery/StrategyHook.sol";
import { TickMath } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

contract DefaultHook is StrategyHook {
    using FixedPointMathLib for uint256;
    /* //////////////////////////////////////////////////////////////
                               STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from an Arcadia Account to a struct with Account-specific strategy information.
    mapping(address rebalancer => mapping(address account => StrategyInfo)) public strategyInfo;

    // A struct containing Account-specific strategy information.
    struct StrategyInfo {
        // The contract address of token0.
        address token0;
        // The contract address of token1.
        address token1;
        // A bytes array containing custom strategy information.
        bytes customInfo;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidTokens();

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the Rebalancer to set the strategy info for an Account.
     * @param account The contract address of the Arcadia Account to set the rebalance info for.
     * @param strategyData Encoded data containing strategy parameters.
     */
    function setStrategy(address account, bytes calldata strategyData) external override {
        (address token0, address token1, bytes memory customInfo) = abi.decode(strategyData, (address, address, bytes));
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        strategyInfo[msg.sender][account] = StrategyInfo({ token0: token0, token1: token1, customInfo: customInfo });
    }

    /* //////////////////////////////////////////////////////////////
                        BEFORE REBALANCE HOOK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the rebalance is executed.
     * @param account The contract address of the Arcadia Account.
     * param positionManager The contract address of the Position Manager.
     * @param position The state of the old position.
     * @param strategyData Encoded data containing strategy parameters.
     * @return tickLower The new lower tick to rebalance to.
     * @return tickUpper The new upper tick to rebalance to.
     * @dev If no new range for the position was passed in the strategyData,
     * then the new position will be a 50/50 position around the current sqrtPrice with same range as the old position.
     * @dev We do not handle the edge cases where the new ticks might exceed MIN_TICK or MAX_TICK.
     * This will result in a revert during the mint, if ever needed a different rebalancer has to be deployed.
     */
    function beforeRebalance(address account, address, PositionState memory position, bytes memory strategyData)
        external
        view
        override
        returns (int24 tickLower, int24 tickUpper)
    {
        if (
            position.tokens[0] != strategyInfo[msg.sender][account].token0
                || position.tokens[1] != strategyInfo[msg.sender][account].token1
        ) {
            revert InvalidTokens();
        }

        if (strategyData.length > 0) {
            // If a new range for the position was passed in the strategyData, use that.
            (tickLower, tickUpper) = abi.decode(strategyData, (int24, int24));
        } else {
            // If not, tind the optimal ticks around current tick that approxmates a 50/50 position around the current sqrtPrice as close as possible.
            int24 tickRange = position.tickUpper - position.tickLower;
            // The logic is different depending if the range is an even or uneven multiple of tick spacings.
            if ((tickRange / position.tickSpacing) % 2 == 1) {
                // For tick ranges that are an uneven multiple of the tick spacing,
                // we use the same number of tick spacings below and above the tick spacing of the current tick.
                // If we have for instance a position with a range of 5 tick spacings:
                // - The tickLower will be 2 tick spacings below the first tick that can be initialised below tickCurrent.
                // - The tickUpper will be 2 tick spacings above the first tick that can be initialised above tickCurrent.
                //   (which is 3 tick spacings above the first tick that can be initialised below tickCurrent).
                int24 tickInitializableBelowCurrent = position.tickCurrent / position.tickSpacing * position.tickSpacing;
                tickLower =
                    tickInitializableBelowCurrent - tickRange / (2 * position.tickSpacing) * position.tickSpacing;
            } else {
                // For tick ranges that are an even multiple of the tick spacing,
                // we use a symmetric spacing initializable tick that is closest to the current sqrtPrice.
                // If we have for instance a position with a range of 4 tick spacings,
                // and the current sqrtPrice is closest to first tick that can be initialised below tickCurrent:
                // - The tickLower will be 2 tick spacing below that tick.
                // - The tickUpper will be 2 tick spacings above that tick.
                // And vica versa when the current sqrtPrice is closest to first tick that can be initialised above tickCurrent.
                int24 tickClosest =
                    _getClosestInitializableTick(position.tickSpacing, position.tickCurrent, position.sqrtPrice);
                tickLower = tickClosest - tickRange / 2;
            }
            tickUpper = tickLower + tickRange;
        }
    }

    /**
     * @notice Calculates the closest initializable tick to the current sqrtPrice.
     * @param tickSpacing The tick spacing of the pool.
     * @param tickCurrent The current tick.
     * @param sqrtPrice The current sqrtPrice.
     * @return tickClosest TThe closest initializable tick to the current sqrtPrice.
     */
    function _getClosestInitializableTick(int24 tickSpacing, int24 tickCurrent, uint256 sqrtPrice)
        internal
        pure
        returns (int24 tickClosest)
    {
        // Get the closest initializable tick below and above the current tick.
        int24 tickBelow = tickCurrent / tickSpacing * tickSpacing;
        int24 tickAbove = tickBelow + tickSpacing;
        uint256 sqrtPriceBelow = TickMath.getSqrtPriceAtTick(tickBelow);
        uint256 sqrtPriceAbove = TickMath.getSqrtPriceAtTick(tickAbove);

        // Find the initializable tick that is closest to the current sqrtPrice.
        tickClosest = (sqrtPriceAbove.mulDivDown(1e18, sqrtPrice) > sqrtPrice.mulDivDown(1e18, sqrtPriceBelow))
            ? tickBelow
            : tickBelow + tickSpacing;
    }

    /* //////////////////////////////////////////////////////////////
                         AFTER REBALANCE HOOK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called after the rebalance is executed.
     * param account The contract address of the Arcadia Account.
     * param positionManager The contract address of the Position Manager.
     * param oldId The oldId of the Liquidity Position.
     * param newPosition The state of the new position.
     * param strategyData Encoded data containing strategy parameters.
     */
    function afterRebalance(address, address, uint256, PositionState memory, bytes memory) external override { }
}
