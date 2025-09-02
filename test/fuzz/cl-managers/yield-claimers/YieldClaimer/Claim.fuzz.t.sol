/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
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
    function testFuzz_Revert_claim_Paused(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Yield Claimer is Paused.
        vm.prank(users.owner);
        yieldClaimer.setPauseFlag(true);

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        yieldClaimer.claim(account_, initiatorParams);
    }

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
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
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
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: YieldClaimer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(yieldClaimer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: YieldClaimer is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), initiatorParams);
    }
}
