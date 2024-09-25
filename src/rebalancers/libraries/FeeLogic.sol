/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";

library FeeLogic {
    using SafeTransferLib for ERC20;

    /**
     * @notice Transfers the initiator fee to the initiator.
     * @param initiator The address of the initiator.
     * @param zeroToOne Bool indicating if token0 has to be swapped to token1 or opposite.
     * @param amountInitiatorFee The amount of initiator fee.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param balance0 The balance of token0 before transferring the initiator fee.
     * @param balance1 The balance of token1 before transferring the initiator fee.
     * @return balance0 The balance of token0 after transferring the initiator fee.
     * @return balance1 The balance of token1 after transferring the initiator fee.
     */
    function _transfer(
        address initiator,
        bool zeroToOne,
        uint256 amountInitiatorFee,
        address token0,
        address token1,
        uint256 balance0,
        uint256 balance1
    ) internal returns (uint256, uint256) {
        if (zeroToOne) {
            if (balance0 > amountInitiatorFee) {
                balance0 -= amountInitiatorFee;
            } else {
                amountInitiatorFee = balance0;
                balance0 = 0;
            }
            if (amountInitiatorFee > 0) ERC20(token0).safeTransfer(initiator, amountInitiatorFee);
        } else {
            if (balance1 > amountInitiatorFee) {
                balance1 -= amountInitiatorFee;
            } else {
                amountInitiatorFee = balance1;
                balance1 = 0;
            }
            if (amountInitiatorFee > 0) ERC20(token1).safeTransfer(initiator, amountInitiatorFee);
        }
        return (balance0, balance1);
    }
}
