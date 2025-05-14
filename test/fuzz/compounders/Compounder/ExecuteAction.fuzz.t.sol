/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../src/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "Compounder".
 */
contract ExecuteAction_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
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
        compounder.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Compounder.OnlyAccount.selector);
        compounder.executeAction(rebalanceData);
        vm.stopPrank();
    }
}
