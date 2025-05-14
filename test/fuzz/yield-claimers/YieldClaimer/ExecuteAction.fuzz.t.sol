/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "YieldClaimer".
 */
contract ExecuteAction_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: account is set.
        yieldClaimer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(YieldClaimer.OnlyAccount.selector);
        yieldClaimer.executeAction(rebalanceData);
        vm.stopPrank();
    }
}
