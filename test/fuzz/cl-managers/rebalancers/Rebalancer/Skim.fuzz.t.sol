/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { RevertingReceive } from "../../../../../lib/accounts-v2/test/utils/mocks/RevertingReceive.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "Rebalancer".
 */
contract Skim_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_skim_NonOwner(address nonOwner, address token) public {
        // Given: Non-owner is not the owner of the rebalancer.
        vm.assume(nonOwner != users.owner);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        rebalancer.skim(token);
    }

    function testFuzz_Revert_skim_Paused(address token) public {
        // Given : rebalancer is Paused.
        vm.prank(users.owner);
        rebalancer.setPauseFlag(true);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Guardian.Paused.selector);
        rebalancer.skim(token);
    }

    function testFuzz_Revert_compound_Reentered(address account_, address token) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.skim(token);
    }

    function testFuzz_Revert_skim_NativeToken_Receive(uint256 amount) public {
        // Given: Owner cannot receive native tokens.
        RevertingReceive revertingReceiver = new RevertingReceive();
        vm.prank(users.owner);
        rebalancer.transferOwnership(address(revertingReceiver));

        // And: meklOperator has a native token balance.
        uint256 balancePre = address(revertingReceiver).balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(revertingReceiver), amount);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(address(revertingReceiver));
        vm.expectRevert(RevertingReceive.TestError.selector);
        rebalancer.skim(address(0));
    }

    function testFuzz_Success_skim_Ether(uint256 amount) public {
        // Given: meklOperator has a native token balance.
        uint256 balancePre = users.owner.balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(rebalancer), amount);

        // When: Calling skim.
        vm.prank(users.owner);
        rebalancer.skim(address(0));

        // Then: The balance of the rebalancer should be updated.
        assertEq(address(rebalancer).balance, 0);

        // And: Owner should receive the tokens.
        assertEq(users.owner.balance, balancePre + amount);
    }

    function testFuzz_Success_skim_ERC20(uint256 amount) public {
        // Given: meklOperator has an ERC20 balance.
        deal(address(token0), address(rebalancer), amount, true);

        // When: Calling skim.
        vm.prank(users.owner);
        rebalancer.skim(address(token0));

        // Then: The balance of the rebalancer should be updated.
        assertEq(token0.balanceOf(address(rebalancer)), 0);

        // And: Owner should receive the tokens.
        assertEq(token0.balanceOf(users.owner), amount);
    }
}
