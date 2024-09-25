/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorForAccount" of contract "Rebalancer".
 */
contract SetInitiatorForAccount_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setInitiatorForAccount_NotAnAccount(address caller, address initiator, address account_)
        public
    {
        // Given : account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When : calling rebalancePosition
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.NotAnAccount.selector);
        rebalancer.setInitiatorForAccount(initiator, account_);
    }

    function testFuzz_Revert_setInitiatorForAccount_OnlyAccountOwner(address caller, address initiator) public {
        // Given : caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When : A random address calls setInitiator on the rebalancer
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.OnlyAccountOwner.selector);
        rebalancer.setInitiatorForAccount(initiator, address(account));
    }

    function testFuzz_Success_setInitiatorForAccount(address owner, address initiator) public {
        // Given : account is a valid Arcadia Account
        // When : Owner calls setInitiator on the rebalancer
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initiator, address(account));

        // Then : Initiator should be set for that Account
        assertEq(rebalancer.accountToInitiator(address(account)), initiator);
    }
}
