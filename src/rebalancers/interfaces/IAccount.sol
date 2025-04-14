/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

interface IAccount {
    function flashAction(address actionTarget, bytes calldata actionData) external;
    function owner() external returns (address owner_);
}
