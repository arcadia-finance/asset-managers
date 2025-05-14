/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../src/compounders/Compounder2.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Compounder".
 */
contract SetAccountInfo_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setAccountInfo_Reentered(address caller, address account_, address initiator) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.setAccountInfo(account_, initiator);
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(address caller, address account_, address initiator) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.NotAnAccount.selector);
        compounder.setAccountInfo(account_, initiator);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the compounder
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.OnlyAccountOwner.selector);
        compounder.setAccountInfo(address(account), initiator);
    }

    function testFuzz_Success_setAccountInfo(address initiator) public {
        // Given: account is a valid Arcadia Account
        // When: Owner calls setInitiator on the compounder
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator);

        // Then: Initiator should be set for that Account
        assertEq(compounder.accountToInitiator(account.owner(), address(account)), initiator);
    }
}
