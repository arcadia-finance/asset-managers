/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external payable;
}
