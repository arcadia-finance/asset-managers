/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

interface IAccount {
    function flashAction(address actionTarget, bytes calldata actionData) external;
    function owner() external returns (address);
}
