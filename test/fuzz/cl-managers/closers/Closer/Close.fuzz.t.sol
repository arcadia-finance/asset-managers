/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";

/**
 * @notice Fuzz tests for the function "close" of contract "Closer".
 */
contract Close_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();

        // Set up account info for valid close operations.
        vm.prank(users.accountOwner);
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_close_Paused(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Closer is paused.
        vm.prank(users.owner);
        closer.setPauseFlag(true);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Guardian.Paused.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_Reentered(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));

        // And: account is set (triggering reentry guard).
        closer.setAccount(account_);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.Reentered.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidAccount(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));

        // When : calling close
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        closer.close(account_, initiatorParams);
    }

    function testFuzz_Revert_close_InvalidInitiator(Closer.InitiatorParams memory initiatorParams, address caller_)
        public
    {
        // Given: Caller is not address(0).
        vm.assume(caller_ != address(0));

        // And: Owner of the account has not set an initiator yet.

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_ChangeAccountOwnership(
        Closer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given: newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And: initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Closer is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = 0;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When: calling close.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_InvalidPositionManager(
        Closer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        address initiator
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");

        // When: Initiator owner calls close with excessive claim fee.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidPositionManager.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_InvalidClaimFee(
        Closer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        address initiator
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");

        // And: Position manager is valid.
        closer.setReturnValue(true);

        // And: claimFee is bigger than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, maxClaimFee + 1, type(uint64).max));

        // When: Initiator owner calls close with excessive claim fee.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_InvalidWithdrawAmount(
        Closer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        address initiator
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");

        // And: Position manager is valid.
        closer.setReturnValue(true);

        // And: claimFee is smaller or equal to maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, maxClaimFee));

        // And: withdrawAmount is greater than maxRepayAmount.
        initiatorParams.withdrawAmount = bound(initiatorParams.withdrawAmount, 1, type(uint256).max);
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, initiatorParams.withdrawAmount - 1);

        // When: Initiator calls close with withdrawAmount > maxRepayAmount.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }
}
