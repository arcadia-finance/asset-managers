/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MerklOperatorBase } from "../../../../src/merkl-operator/MerklOperatorBase.sol";
import { MerklOperatorBase_Fuzz_Test } from "./_MerklOperatorBase.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "onSetMerklOperator" of contract "MerklOperatorBase".
 */
contract OnSetMerklOperatorBase_MerklOperatorBase_Fuzz_Test is MerklOperatorBase_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperatorBase_Fuzz_Test.setUp();
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
        vm.expectRevert(MerklOperatorBase.NotAnAccount.selector);
        merklOperator.onSetMerklOperator(accountOwner, status, data);
    }

    function testFuzz_Success_onSetMerklOperator(address accountOwner, bool status, address initiator) public {
        // Given: Valid Account version.
        // When: Owner calls onSetMerklOperator on the merklOperator
        bytes memory data = abi.encode(initiator, "");
        vm.prank(address(account));
        merklOperator.onSetMerklOperator(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(merklOperator.accountToInitiator(accountOwner, address(account)), initiator);
    }
}
