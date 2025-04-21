/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FeeCollector } from "../../../src/yield-routers/FeeCollector.sol";

contract FeeCollectorExtension is FeeCollector {
    constructor(uint256 maxInitiatorFee) FeeCollector(maxInitiatorFee) { }

    function setAccount(address account_) external {
        account = account_;
    }

    function getAccount() external view returns (address account_) {
        account_ = account;
    }
}
