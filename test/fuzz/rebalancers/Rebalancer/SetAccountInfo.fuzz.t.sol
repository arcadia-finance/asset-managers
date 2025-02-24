/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Rebalancer".
 */
contract SetAccountInfo_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address account__,
        address initiator,
        address hook
    ) public {
        // Given: A rebalance is ongoing.
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.setAccountInfo(account__, initiator, hook);
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        address hook
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.NotAnAccount.selector);
        rebalancer.setAccountInfo(account_, initiator, hook);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator, address hook) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.OnlyAccountOwner.selector);
        rebalancer.setAccountInfo(address(account), initiator, hook);
    }

    function testFuzz_Success_setAccountInfo(address initiator, address hook) public {
        // Given: account is a valid Arcadia Account
        // When: Owner calls setInitiator on the rebalancer
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, hook);

        // Then: Initiator should be set for that Account
        assertEq(rebalancer.accountToInitiator(address(account)), initiator);

        // And: Hook should be set for that Account.
        assertEq(rebalancer.strategyHook(address(account)), hook);
    }
}
