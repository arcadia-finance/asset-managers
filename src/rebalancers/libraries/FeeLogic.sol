/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { ERC20, SafeTransferLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";

library FeeLogic {
    using SafeTransferLib for ERC20;

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
