/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract Claim_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_claim_Reentered(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidAccount(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidInitiator(YieldClaimer.InitiatorParams memory initiatorParams, address caller)
        public
    {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_ChangeAccountOwnership(
        YieldClaimer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator,
        uint256 fee
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: YieldClaimer is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: YieldClaimer is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: The initiator is set.
        fee = bound(fee, 0.001 * 1e18, MAX_FEE);
        vm.prank(initiator);
        yieldClaimer.setInitiatorInfo(fee);
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account));

        // And: Account is transferred to newOwner.
        vm.startPrank(account.owner());
        factory.safeTransferFrom(account.owner(), newOwner, address(account));
        vm.stopPrank();

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), initiatorParams);
    }
}
