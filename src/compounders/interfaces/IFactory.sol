/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

interface IFactory {
    function isAccount(address account) external view returns (bool);
}
