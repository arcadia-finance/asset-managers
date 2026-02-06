/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.0;

interface IAccount {
    // forge-lint: disable-next-line(mixed-case-function)
    function ACCOUNT_VERSION() external returns (uint256 version);
    function creditor() external returns (address creditor_);
    function flashAction(address actionTarget, bytes calldata actionData) external;
    function owner() external returns (address owner_);
    function numeraire() external returns (address numeraire_);
}
