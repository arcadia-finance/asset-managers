/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer2.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "YieldClaimer".
 */
contract SetAccountInfo_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address initiator,
        address recipient
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.setAccountInfo(account_, initiator, recipient);
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        address recipient
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.NotAnAccount.selector);
        yieldClaimer.setAccountInfo(account_, initiator, recipient);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator, address recipient)
        public
    {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setAccountInfo on the yieldClaimer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.OnlyAccountOwner.selector);
        yieldClaimer.setAccountInfo(address(account), initiator, recipient);
    }

    function testFuzz_Revert_setAccountInfo_InvalidRecipient(address initiator) public {
        // Given: caller is the Arcadia Account owner.
        // When: Owner calls setAccountInfo with zero address as recipient.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(YieldClaimer.InvalidRecipient.selector);
        yieldClaimer.setAccountInfo(address(account), initiator, address(0));
    }

    function testFuzz_Success_setAccountInfo(address initiator, address recipient) public {
        // Given: Recipient is not address(0).
        vm.assume(recipient != address(0));

        // When: Owner calls setAccountInfo on the yieldClaimer
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, recipient);

        // Then: Initiator should be set for that Account
        assertEq(yieldClaimer.accountToInitiator(account.owner(), address(account)), initiator);
        assertEq(yieldClaimer.accountToRecipient(address(account)), recipient);
    }
}
