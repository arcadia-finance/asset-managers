/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";
import { RevertingReceive } from "../../../../../lib/accounts-v2/test/utils/mocks/RevertingReceive.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "YieldClaimer".
 */
contract Skim_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_skim_NonOwner(address nonOwner, address token) public {
        // Given: Non-owner is not the owner of the yieldClaimer.
        vm.assume(nonOwner != users.owner);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        yieldClaimer.skim(token);
    }

    function testFuzz_Revert_skim_Paused(address token) public {
        // Given : yieldClaimer is Paused.
        vm.prank(users.owner);
        yieldClaimer.setPauseFlag(true);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Guardian.Paused.selector);
        yieldClaimer.skim(token);
    }

    function testFuzz_Revert_compound_Reentered(address account_, address token) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.skim(token);
    }

    function testFuzz_Revert_skim_NativeToken_Receive(uint256 amount) public {
        // Given: Owner cannot receive native tokens.
        RevertingReceive revertingReceiver = new RevertingReceive();
        vm.prank(users.owner);
        yieldClaimer.transferOwnership(address(revertingReceiver));

        // And: merklOperator has a native token balance.
        uint256 balancePre = address(revertingReceiver).balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(revertingReceiver), amount);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(address(revertingReceiver));
        vm.expectRevert(RevertingReceive.TestError.selector);
        yieldClaimer.skim(address(0));
    }

    function testFuzz_Success_skim_Ether(uint256 amount) public {
        // Given: merklOperator has a native token balance.
        uint256 balancePre = users.owner.balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(yieldClaimer), amount);

        // When: Calling skim.
        vm.prank(users.owner);
        yieldClaimer.skim(address(0));

        // Then: The balance of the yieldClaimer should be updated.
        assertEq(address(yieldClaimer).balance, 0);

        // And: Owner should receive the tokens.
        assertEq(users.owner.balance, balancePre + amount);
    }

    function testFuzz_Success_skim_ERC20(uint256 amount) public {
        // Given: merklOperator has an ERC20 balance.
        deal(address(token0), address(yieldClaimer), amount, true);

        // When: Calling skim.
        vm.prank(users.owner);
        yieldClaimer.skim(address(token0));

        // Then: The balance of the yieldClaimer should be updated.
        assertEq(token0.balanceOf(address(yieldClaimer)), 0);

        // And: Owner should receive the tokens.
        assertEq(token0.balanceOf(users.owner), amount);
    }
}
