/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { RebalancerUniV3Slipstream } from "../../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RebalancerUniV3Slipstream_Fuzz_Test } from "./_RebalancerUniV3Slipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "RebalancerUniV3Slipstream".
 */
contract SetAccountInfo_RebalancerUniV3Slipstream_Fuzz_Test is RebalancerUniV3Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniV3Slipstream_Fuzz_Test.setUp();
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

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(RebalancerUniV3Slipstream.Reentered.selector);
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
        vm.expectRevert(RebalancerUniV3Slipstream.NotAnAccount.selector);
        rebalancer.setAccountInfo(account_, initiator, hook);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator, address hook) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(RebalancerUniV3Slipstream.OnlyAccountOwner.selector);
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
