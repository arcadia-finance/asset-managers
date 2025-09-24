/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../state/PositionState.sol";

/**
 * @title Abstract Strategy Hook.
 * @notice Allows an Arcadia Account to verify custom rebalancing preferences, such as:
 * - The id or the underlying tokens of the position
 * - Directional Preferences.
 * - Minimum Cool Down periods.
 * - ...
 */
abstract contract StrategyHook {
    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the Rebalancer to set the strategy info for an Account.
     * @param account The contract address of the Arcadia Account to set the rebalance info for.
     * @param strategyData Encoded data containing strategy parameters.
     */
    function setStrategy(address account, bytes calldata strategyData) external virtual;

    /* //////////////////////////////////////////////////////////////
                        BEFORE REBALANCE HOOK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the rebalance is executed.
     * @param account The contract address of the Arcadia Account.
     * @param positionManager The contract address of the Position Manager.
     * @param position The state of the old position.
     * @param strategyData Encoded data containing strategy parameters.
     * @return tickLower The new lower tick to rebalance to.
     * @return tickUpper The new upper tick to rebalance to.
     */
    function beforeRebalance(
        address account,
        address positionManager,
        PositionState memory position,
        bytes memory strategyData
    ) external view virtual returns (int24 tickLower, int24 tickUpper);

    /* //////////////////////////////////////////////////////////////
                         AFTER REBALANCE HOOK
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called after the rebalance is executed.
     * @param account The contract address of the Arcadia Account.
     * @param positionManager The contract address of the Position Manager.
     * @param oldId The oldId of the Liquidity Position.
     * @param newPosition The state of the new position.
     * @param strategyData Encoded data containing strategy parameters.
     */
    function afterRebalance(
        address account,
        address positionManager,
        uint256 oldId,
        PositionState memory newPosition,
        bytes memory strategyData
    ) external virtual;
}
