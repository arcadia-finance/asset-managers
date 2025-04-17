/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/token-claimers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "executeAction" of contract "AeroClaimer".
 */
contract ExecuteAction_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        AeroClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_executeAction_OnlyAccount(address notAccount, address account) public {
        // Given: An account address is defined in storage.
        aeroClaimer.setAccount(account);

        // When: A not valid address calls executeAction();
        // Then: It should revert.
        vm.prank(notAccount);
        vm.expectRevert(AeroClaimer.OnlyAccount.selector);
        aeroClaimer.executeAction("");
    }

    // All others cases are covered by our full flow testing in ClaimAero.fuzz.t.sol
}
