// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

interface IGPv2Settlement {
    function domainSeparator() external returns (bytes32);
    function filledAmount(bytes calldata orderUid) external returns (uint256 amount);
    function setPreSignature(bytes calldata orderUid, bool signed) external;
    function vaultRelayer() external returns (address);
}
