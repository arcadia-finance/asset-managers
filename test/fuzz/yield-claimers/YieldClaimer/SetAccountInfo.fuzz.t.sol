/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "YieldClaimer".
 */
contract SetAccountInfo_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setAccountInfo_Reentered(address random, address initiator_, address recipient_) public {
        // Given: Account is not address(0).
        vm.assume(random != address(0));

        // And: An account address is defined in storage.
        yieldClaimer.setAccount(random);

        // When: Calling setAccountInfo().
        // Then: It should revert.
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.setAccountInfo(address(account), initiator_, recipient_);
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(address initiator_, address notAccount, address recipient_)
        public
    {
        // Given: Address passed is not an Arcadia Account.
        vm.assume(notAccount != address(account));
        // When: Calling setAccountInfo().
        // Then: It should revert.
        vm.expectRevert(YieldClaimer.NotAnAccount.selector);
        yieldClaimer.setAccountInfo(notAccount, initiator_, recipient_);
    }

    function testFuzz_Revert_setAccountInfoFee_OnlyAccountOwner(address caller, address initiator_, address recipient_)
        public
    {
        // Given: Caller is not accountOwner.
        vm.assume(caller != account.owner());

        // When: Calling setAccountInfo().
        // Then: It should revert.
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.OnlyAccountOwner.selector);
        yieldClaimer.setAccountInfo(address(account), initiator_, recipient_);
    }

    function testFuzz_Revert_setAccountInfoFee_InvalidRecipient(address initiator_) public {
        // Given: recipient_ is address(0).
        address recipient_ = address(0);

        // When: Calling setAccountInfo().
        // Then: It should revert.
        vm.prank(users.accountOwner);
        vm.expectRevert(YieldClaimer.InvalidRecipient.selector);
        yieldClaimer.setAccountInfo(address(account), initiator_, recipient_);
    }

    function testFuzz_Success_setAccountInfo(address initiator_, address recipient_) public {
        // Given: recipient_ is not address(0).
        vm.assume(recipient_ != address(0));

        // When: Calling setAccountInfo().
        vm.prank(users.accountOwner);
        vm.expectEmit();
        emit YieldClaimer.AccountInfoSet(address(account), initiator_, recipient_);
        yieldClaimer.setAccountInfo(address(account), initiator_, recipient_);

        // Then: Initiator should be set.
        assertEq(yieldClaimer.accountToInitiator(address(account)), initiator_);
        assertEq(yieldClaimer.accountToFeeRecipient(address(account)), recipient_);
    }
}
