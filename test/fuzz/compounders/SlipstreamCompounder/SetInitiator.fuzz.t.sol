/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiator" of contract "SlipstreamCompounder".
 */
contract SetInitiator_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setInitiator_Reentered(
        address caller,
        address account_,
        address account__,
        address initiator_
    ) public {
        // Given: A rebalance is ongoing.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling compoundFees().
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(SlipstreamCompounder.Reentered.selector);
        compounder.setInitiator(account__, initiator_);
    }

    function testFuzz_Revert_setInitiator_NotAnAccount(address caller, address account_, address initiator_) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling compoundFees().
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(SlipstreamCompounder.NotAnAccount.selector);
        compounder.setInitiator(account_, initiator_);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator_) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the compounder.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(SlipstreamCompounder.OnlyAccountOwner.selector);
        compounder.setInitiator(address(account), initiator_);
    }

    function testFuzz_Success_setAccountInfo(address initiator_) public {
        // Given: account is a valid Arcadia Account
        // When: Owner calls setInitiator on the compounder
        vm.prank(account.owner());
        compounder.setInitiator(address(account), initiator_);

        // Then: Initiator should be set for that Account
        assertEq(compounder.accountToInitiator(address(account)), initiator_);
    }
}
