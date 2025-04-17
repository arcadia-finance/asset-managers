/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/token-claimers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "AeroClaimer".
 */
contract Constructor_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        AeroClaimer aeroClaimer_ = new AeroClaimer(maxInitiatorShare);

        assertEq(aeroClaimer_.MAX_INITIATOR_FEE(), maxInitiatorShare);
    }
}
