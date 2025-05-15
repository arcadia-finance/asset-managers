/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
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
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.setAccountInfo(account_, initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.NotAnAccount.selector);
        yieldClaimer.setAccountInfo(account_, initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(
        address caller,
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setAccountInfo on the yieldClaimer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.OnlyAccountOwner.selector);
        yieldClaimer.setAccountInfo(address(account), initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_InvalidRecipient(
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is the zero address.
        accountInfo.feeRecipient = address(0);

        // When: Owner calls setAccountInfo.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(YieldClaimer.InvalidRecipient.selector);
        yieldClaimer.setAccountInfo(address(account), initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_InvalidValue(address initiator, YieldClaimer.AccountInfo memory accountInfo)
        public
    {
        // Given: recipient is not the zero address.
        vm.assume(accountInfo.feeRecipient != address(0));

        // And: maxClaimFee is bigger than 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setAccountInfo.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(YieldClaimer.InvalidValue.selector);
        yieldClaimer.setAccountInfo(address(account), initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Success_setAccountInfo(address initiator, YieldClaimer.AccountInfo memory accountInfo) public {
        // Given: Recipient is not address(0).
        vm.assume(accountInfo.feeRecipient != address(0));

        // And: maxClaimFee is smaller or equal to 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 0, 1e18));

        // When: Owner calls setAccountInfo on the yieldClaimer
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");

        // Then: Initiator should be set for that Account
        assertEq(yieldClaimer.accountToInitiator(account.owner(), address(account)), initiator);
        (address feeRecipient, uint64 maxClaimFee) = yieldClaimer.accountInfo(address(account));
        assertEq(feeRecipient, accountInfo.feeRecipient);
        assertEq(maxClaimFee, accountInfo.maxClaimFee);
    }
}
