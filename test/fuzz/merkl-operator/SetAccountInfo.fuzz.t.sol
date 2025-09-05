/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MerklOperator } from "../../../src/merkl-operator/MerklOperator.sol";
import { MerklOperator_Fuzz_Test } from "./_MerklOperator.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "MerklOperator".
 */
contract SetAccountInfo_MerklOperator_Fuzz_Test is MerklOperator_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperator_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperator.NotAnAccount.selector);
        merklOperator.setAccountInfo(account_, initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(
        address caller,
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setAccountInfo on the merklOperator
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperator.OnlyAccountOwner.selector);
        merklOperator.setAccountInfo(
            address(account), initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidRewardRecipient(
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is the zero address.
        accountInfo.rewardRecipient = address(0);

        // When: Owner calls setAccountInfo.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(MerklOperator.InvalidRewardRecipient.selector);
        merklOperator.setAccountInfo(
            address(account), initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidValue(
        address initiator,
        MerklOperator.AccountInfo memory accountInfo
    ) public {
        // Given: recipient is not the zero address.
        vm.assume(accountInfo.rewardRecipient != address(0));

        // And: maxClaimFee is bigger than 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setAccountInfo.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(MerklOperator.InvalidValue.selector);
        merklOperator.setAccountInfo(
            address(account), initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, ""
        );
    }

    function testFuzz_Success_setAccountInfo(address initiator, MerklOperator.AccountInfo memory accountInfo) public {
        // Given: Recipient is not address(0).
        vm.assume(accountInfo.rewardRecipient != address(0));

        // And: maxClaimFee is smaller or equal to 1e18.
        accountInfo.maxClaimFee = uint64(bound(accountInfo.maxClaimFee, 0, 1e18));

        // When: Owner calls setAccountInfo on the merklOperator
        vm.prank(account.owner());
        merklOperator.setAccountInfo(
            address(account), initiator, accountInfo.rewardRecipient, accountInfo.maxClaimFee, ""
        );

        // Then: Initiator should be set for that Account
        assertEq(merklOperator.accountToInitiator(account.owner(), address(account)), initiator);
        (address rewardRecipient, uint64 maxClaimFee) = merklOperator.accountInfo(address(account));
        assertEq(rewardRecipient, accountInfo.rewardRecipient);
        assertEq(maxClaimFee, accountInfo.maxClaimFee);
    }
}
