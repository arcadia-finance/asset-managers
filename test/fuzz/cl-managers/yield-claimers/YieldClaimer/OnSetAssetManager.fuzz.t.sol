/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "onSetAssetManager" of contract "YieldClaimer".
 */
contract OnSetAssetManager_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_onSetAssetManager_Reentered(
        address caller,
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetMerklOperator_NotAnAccount(
        address caller,
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: account_ is not an Arcadia Account.
        vm.assume(account_ != address(account));

        // When: Calling onSetAssetManager.
        // Then: It should revert.
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.NotAnAccount.selector);
        yieldClaimer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidRecipient(
        address accountOwner,
        bool status,
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is the zero address.
        accountInfo.feeRecipient = address(0);

        // When: Owner calls onSetAssetManager.
        // Then: it should revert
        bytes memory data = abi.encode(initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        vm.expectRevert(YieldClaimer.InvalidRecipient.selector);
        yieldClaimer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidValue(
        address accountOwner,
        bool status,
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is not the zero address.
        vm.assume(accountInfo.feeRecipient != address(0));

        // And: maxClaimFee is bigger than 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls onSetAssetManager.
        // Then: it should revert
        bytes memory data = abi.encode(initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        vm.expectRevert(YieldClaimer.InvalidValue.selector);
        yieldClaimer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Success_onSetAssetManager(
        address accountOwner,
        bool status,
        address initiator,
        YieldClaimer.AccountInfo memory accountInfo
    ) public {
        // Given: Recipient is not address(0).
        vm.assume(accountInfo.feeRecipient != address(0));

        // And: maxClaimFee is smaller or equal to 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 0, 1e18));

        // When: Owner calls onSetAssetManager on the yieldClaimer
        bytes memory data = abi.encode(initiator, accountInfo.feeRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        yieldClaimer.onSetAssetManager(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(yieldClaimer.accountToInitiator(accountOwner, address(account)), initiator);
        (address feeRecipient, uint64 maxClaimFee) = yieldClaimer.accountInfo(address(account));
        assertEq(feeRecipient, accountInfo.feeRecipient);
        assertEq(maxClaimFee, accountInfo.maxClaimFee);
    }
}
