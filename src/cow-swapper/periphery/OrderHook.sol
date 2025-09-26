/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { IOrderHook } from "../interfaces/IOrderHook.sol";

/**
 * @title Abstract Strategy Hook.
 * @notice Allows an Arcadia Account to verify custom rebalancing preferences, such as:
 * - The id or the underlying tokens of the position
 * - Directional Preferences.
 * - Minimum Cool Down periods.
 * - ...
 */
abstract contract OrderHook is IOrderHook {
    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the CoW Swapper to set the Account specific information.
     * @param account The contract address of the Arcadia Account to set the rebalance info for.
     * @param hookData Encoded data containing hook specific parameters.
     */
    function setHook(address account, bytes calldata hookData) external virtual;

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the swap is executed.
     * @param account The contract address of the Arcadia Account.
     * @param order The CoW Swap order.
     * @return Bool indicating if the order is valid.
     */
    function isValidOrder(address account, GPv2Order.Data memory order) external view virtual returns (bool);
}
