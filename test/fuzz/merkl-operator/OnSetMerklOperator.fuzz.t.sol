/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MerklOperator } from "../../../src/merkl-operator/MerklOperator.sol";
import { MerklOperator_Fuzz_Test } from "./_MerklOperator.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "onSetMerklOperator" of contract "MerklOperator".
 */
contract OnSetMerklOperator_MerklOperator_Fuzz_Test is MerklOperator_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperator_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_onSetMerklOperator_NotAnAccount(
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: account_ is not an Arcadia Account.
        vm.assume(account_ != address(account));

        // When: Calling onSetMerklOperator.
        // Then: It should revert.
        vm.prank(account_);
        vm.expectRevert(MerklOperator.NotAnAccount.selector);
        merklOperator.onSetMerklOperator(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetMerklOperator_InvalidRewardRecipient(
        address accountOwner,
        bool status,
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is the zero address.
        accountInfo.rewardRecipient = address(0);

        // When: Owner calls onSetMerklOperator.
        // Then: It should revert
        bytes memory data = abi.encode(initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        vm.expectRevert(MerklOperator.InvalidRewardRecipient.selector);
        merklOperator.onSetMerklOperator(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetMerklOperator_InvalidValue(
        address accountOwner,
        bool status,
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is not the zero address.
        vm.assume(accountInfo.rewardRecipient != address(0));

        // And: maxClaimFee is bigger than 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls onSetMerklOperator.
        // Then: It should revert
        bytes memory data = abi.encode(initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        vm.expectRevert(MerklOperator.InvalidValue.selector);
        merklOperator.onSetMerklOperator(accountOwner, status, data);
    }

    function testFuzz_Success_onSetMerklOperator(
        address accountOwner,
        bool status,
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: Recipient is not address(0).
        vm.assume(accountInfo.rewardRecipient != address(0));

        // And: maxClaimFee is smaller or equal to 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 0, 1e18));

        // When: Owner calls onSetMerklOperator on the merklOperator
        bytes memory data = abi.encode(initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, "");
        vm.prank(address(account));
        merklOperator.onSetMerklOperator(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(merklOperator.accountToInitiator(accountOwner, address(account)), initiator);
        (address rewardRecipient, uint64 maxClaimFee) = merklOperator.accountInfo(address(account));
        assertEq(rewardRecipient, accountInfo.rewardRecipient);
        assertEq(maxClaimFee, accountInfo.maxClaimFee);
    }
}
