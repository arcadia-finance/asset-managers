// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

interface IGPv2Settlement {
    function domainSeparator() external returns (bytes32);
    function settlementContract() external view returns (address);
    function vaultRelayer() external returns (address);
}
