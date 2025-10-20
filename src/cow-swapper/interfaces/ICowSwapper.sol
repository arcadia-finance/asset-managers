/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.0;

interface ICowSwapper {
    function beforeSwap(bytes memory hookData) external;
    function settlementContract() external view returns (address);
}
