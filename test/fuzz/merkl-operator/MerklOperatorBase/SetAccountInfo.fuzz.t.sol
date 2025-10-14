/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountVariableVersion } from
    "../../../../lib/accounts-v2/test/utils/mocks/accounts/AccountVariableVersion.sol";
import { MerklOperatorBase } from "../../../../src/merkl-operator/MerklOperatorBase.sol";
import { MerklOperatorBase_Fuzz_Test } from "./_MerklOperatorBase.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "MerklOperatorBase".
 */
contract SetAccountInfo_MerklOperatorBase_Fuzz_Test is MerklOperatorBase_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperatorBase_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setAccountInfo_NotAnAccount(address caller, address account_, address initiator) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperatorBase.NotAnAccount.selector);
        merklOperator.setAccountInfo(account_, initiator, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setAccountInfo on the merklOperator
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(MerklOperatorBase.OnlyAccountOwner.selector);
        merklOperator.setAccountInfo(address(account), initiator, "");
    }

    function testFuzz_Revert_setAccountInfo_InvalidAccountVersion(address initiator, uint256 accountVersion) public {
        // Given: Account has an invalid version.
        accountVersion = bound(accountVersion, 0, 2);
        AccountVariableVersion account_ = new AccountVariableVersion(accountVersion, address(factory));
        stdstore.target(address(factory)).sig(factory.isAccount.selector).with_key(address(account_)).checked_write(
            true
        );
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account_)).checked_write(
            2
        );

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        vm.prank(account_.owner());
        vm.expectRevert(MerklOperatorBase.InvalidAccountVersion.selector);
        merklOperator.setAccountInfo(address(account_), initiator, "");
    }

    function testFuzz_Success_setAccountInfo(address initiator) public {
        // Given: Valid Account version.
        // When: Owner calls setAccountInfo on the merklOperator
        vm.prank(account.owner());
        merklOperator.setAccountInfo(address(account), initiator, "");

        // Then: Initiator should be set for that Account
        assertEq(merklOperator.accountToInitiator(account.owner(), address(account)), initiator);
    }
}
