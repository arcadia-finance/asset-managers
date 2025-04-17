/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/yield-routers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitator" of contract "AeroClaimer".
 */
contract SetInitiator_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        AeroClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setInitiator_Reentered(address random, address initiator_) public {
        // Given: An account address is defined in storage.
        aeroClaimer.setAccount(random);

        // When: Calling setInitiator().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.Reentered.selector);
        aeroClaimer.setInitiator(address(account), initiator_);
    }

    function testFuzz_Revert_setInitiator_NotAnAccount(address initiator_, address notAccount) public {
        // Given: Address passed is not an Arcadia Account.
        vm.assume(notAccount != address(account));
        // When: Calling setInitator().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.NotAnAccount.selector);
        aeroClaimer.setInitiator(notAccount, initiator_);
    }

    function testFuzz_Revert_setInitiatorFee_OnlyAccountOwner(address caller, address initiator_) public {
        // Given: Caller is not accountOwner.
        vm.assume(caller != account.owner());

        // When: Calling setInitiator().
        // Then: It should revert.
        vm.startPrank(caller);
        vm.expectRevert(AeroClaimer.OnlyAccountOwner.selector);
        aeroClaimer.setInitiator(address(account), initiator_);
    }

    function testFuzz_Success_setInitiator(address initiator_) public {
        // Given: Caller is Account owner.
        // When: Calling setInitiator().
        vm.startPrank(users.accountOwner);
        vm.expectEmit();
        emit AeroClaimer.InitiatorSet(address(account), initiator_);
        aeroClaimer.setInitiator(address(account), initiator_);

        // Then: Initiator should be set.
        assertEq(aeroClaimer.accountToInitiator(address(account)), initiator_);
    }
}
