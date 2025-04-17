/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../src/token-claimers/AeroClaimer.sol";

contract AeroClaimerExtension is AeroClaimer {
    constructor(uint256 maxInitiatorShare) AeroClaimer(maxInitiatorShare) { }

    function setAccount(address account_) external {
        account = account_;
    }
}
