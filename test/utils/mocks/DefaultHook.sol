/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../src/rebalancers/Rebalancer.sol";

contract DefaultHook {
    /* //////////////////////////////////////////////////////////////
                               STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from an Arcadia Account to a struct with Account-specific strategy information.
    mapping(address account => StrategyInfo) public strategyInfo;

    // A struct containing Account-specific strategy information.
    struct StrategyInfo {
        address token0;
        address token1;
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
    function setStrategy(address account, bytes calldata strategyData) external {
        (address token0, address token1, bytes memory customInfo) = abi.decode(strategyData, (address, address, bytes));
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        strategyInfo[account] = StrategyInfo({ token0: token0, token1: token1, customInfo: customInfo });
    }

    /* //////////////////////////////////////////////////////////////
                            REBALA?NCE HOOKS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the rebalance is executed.
     * @param account The contract address of the Arcadia Account.
     * param positionManager The contract address of the Position Manager.
     * @param position The state of the old position.
     * @param strategyData Encoded data containing strategy parameters.
     * @return tickLower The new lower tick to rebalance to.
     * @return tickUpper The new upper tick to rebalance to.
     */
    function beforeRebalance(
        address account,
        address,
        Rebalancer.PositionState memory position,
        bytes memory strategyData
    ) external view returns (int24 tickLower, int24 tickUpper) {
        if (position.tokens[0] != strategyInfo[account].token0 || position.tokens[1] != strategyInfo[account].token1) {
            revert InvalidTokens();
        }

        if (strategyData.length > 0) {
            (tickLower, tickUpper) = abi.decode(strategyData, (int24, int24));
        } else {
            int24 tickRange = position.tickUpper - position.tickLower;
            // Round current tick down to a tick that is a multiple of the tick spacing (can be initialised).
            // We do not handle the edge cases where the new ticks might exceed MIN_TICK or MAX_TICK.
            // This will result in a revert during the mint, if ever needed a different rebalancer has to be deployed.
            int24 tickMiddle = position.tickCurrent / position.tickSpacing * position.tickSpacing;
            // For tick ranges that are an even multiple of the tick spacing, we use a symmetric spacing around the current tick.
            // For uneven multiples, the smaller part is below the current tick.
            tickLower = tickMiddle - tickRange / (2 * position.tickSpacing) * position.tickSpacing;
            tickUpper = tickLower + tickRange;
        }
    }

    /**
     * @notice Hook called after the rebalance is executed.
     * param account The contract address of the Arcadia Account.
     * param positionManager The contract address of the Position Manager.
     * param oldId The oldId of the Liquidity Position.
     * param newPosition The state of the new position.
     * param strategyData Encoded data containing strategy parameters.
     */
    function afterRebalance(address, address, uint256, Rebalancer.PositionState memory, bytes memory) external pure { }
}
