/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "Closer".
 */
contract ExecuteAction_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_executeAction_NonAccount(bytes calldata actionTargetData, address caller_) public {
        // Given: Caller is not the account.
        vm.assume(caller_ != address(account));

        // And: account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.OnlyAccount.selector);
        closer.executeAction(actionTargetData);
        vm.stopPrank();
    }
}
