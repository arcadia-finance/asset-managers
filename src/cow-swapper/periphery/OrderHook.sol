/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IOrderHook } from "../interfaces/IOrderHook.sol";

/**
 * @title Abstract Order Hook.
 * @author Pragma Labs
 */
abstract contract OrderHook is IOrderHook {
    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the CoW Swapper to set the Account specific information.
     * @param account The contract address of the Arcadia Account to set the order info for.
     * @param hookData Encoded data containing hook specific parameters.
     */
    function setHook(address account, bytes calldata hookData) external virtual;

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called to validate and calculate the initiator parameters.
     * @param account The contract address of the Arcadia Account.
     * @param tokenIn The contract address of the token to swap from.
     * @param amountIn The amount of tokenIn to swap.
     * @param initiatorData The packed encoded remaining initiator parameters.
     * @return swapFee The fee charged on the amountOut by the initiator, with 18 decimals precision.
     * @return tokenOut The contract address of the token to swap to.
     * @return orderHash The order hash.
     */
    function getInitiatorParams(address account, address tokenIn, uint256 amountIn, bytes calldata initiatorData)
        external
        view
        virtual
        returns (uint64 swapFee, address tokenOut, bytes32 orderHash);
}
