// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8;

import {
    FlashLoanRouter, IBorrower, ICowSettlement
} from "../../../../../lib/flash-loan-router/src/FlashLoanRouter.sol";

contract FlashLoanRouterExtension is FlashLoanRouter {
    constructor(ICowSettlement settlementContract) FlashLoanRouter(settlementContract) { }

    function setPendingBorrower(address borrower) external {
        pendingBorrower = IBorrower(borrower);
    }

    function setPendingDataHash(bytes32 dataHash) external {
        pendingDataHash = dataHash;
    }
}
