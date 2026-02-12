/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

interface ILendingPool {
    function maxWithdraw(address account) external view returns (uint256);
    function repay(uint256 amount, address account) external;
}
