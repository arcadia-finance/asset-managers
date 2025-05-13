/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { HookMock } from "../../../utils/mocks/HookMock.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Rebalancer".
 */
contract SetAccountInfo_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    HookMock internal strategyHook;

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
        address initiator,
        address hook,
        bytes calldata strategyData
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.setAccountInfo(account_, initiator, hook, strategyData);
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
        rebalancer.setAccountInfo(account_, initiator, hook, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator, address hook) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.OnlyAccountOwner.selector);
        rebalancer.setAccountInfo(address(account), initiator, hook, "");
    }

    function testFuzz_Success_setAccountInfo(address initiator, bytes calldata strategyData) public {
        // Given: Strategy hook is deployed.
        strategyHook = new HookMock();

        // And: account is a valid Arcadia Account
        // When: Owner calls setInitiator on the rebalancer
        // Then: It should call the hook.
        vm.expectCall(address(strategyHook), abi.encodeCall(strategyHook.setStrategy, (address(account), strategyData)));
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(strategyHook), strategyData);

        // Then: Initiator should be set for that Account
        assertEq(rebalancer.accountToInitiator(account.owner(), address(account)), initiator);

        // And: Hook should be set for that Account.
        assertEq(rebalancer.strategyHook(address(account)), address(strategyHook));
    }
}
