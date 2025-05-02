/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "Rebalancer".
 */
contract ExecuteAction_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
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
        rebalancer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Rebalancer.OnlyAccount.selector);
        rebalancer.executeAction(rebalanceData);
        vm.stopPrank();
    }
}
