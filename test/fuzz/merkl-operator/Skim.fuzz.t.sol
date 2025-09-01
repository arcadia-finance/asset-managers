/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { MerklOperator } from "../../../src/merkl-operator/MerklOperator.sol";
import { MerklOperator_Fuzz_Test } from "./_MerklOperator.fuzz.t.sol";
import { RevertingReceive } from "../../../lib/accounts-v2/test/utils/mocks/RevertingReceive.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "MerklOperator".
 */
contract Skim_MerklOperator_Fuzz_Test is MerklOperator_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MerklOperator_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_skim_NonOwner(address nonOwner, address token) public {
        // Given: Non-owner is not the owner of the merklOperator.
        vm.assume(nonOwner != users.owner);

        // When: Calling skim.
        // Then: It should revert.
        vm.startPrank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        merklOperator.skim(token);
        vm.stopPrank();
    }

    function testFuzz_Revert_skim_NativeToken_Receive(uint256 amount) public {
        // Given: Owner cannot receive native tokens.
        RevertingReceive revertingReceiver = new RevertingReceive();
        vm.prank(users.owner);
        merklOperator.transferOwnership(address(revertingReceiver));

        // And: meklOperator has a native token balance.
        uint256 balancePre = address(revertingReceiver).balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(revertingReceiver), amount);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(address(revertingReceiver));
        vm.expectRevert(RevertingReceive.TestError.selector);
        merklOperator.skim(address(0));
    }

    function testFuzz_Success_skim_Ether(uint256 amount) public {
        // Given: meklOperator has a native token balance.
        uint256 balancePre = users.owner.balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(merklOperator), amount);

        // When: Calling skim.
        vm.prank(users.owner);
        merklOperator.skim(address(0));

        // Then: The balance of the merklOperator should be updated.
        assertEq(address(merklOperator).balance, 0);

        // And: Owner should receive the tokens.
        assertEq(users.owner.balance, balancePre + amount);
    }

    function testFuzz_Success_skim_ERC20(uint256 amount) public {
        // Given: meklOperator has an ERC20 balance.
        deal(address(token0), address(merklOperator), amount, true);

        // When: Calling skim.
        vm.prank(users.owner);
        merklOperator.skim(address(token0));

        // Then: The balance of the merklOperator should be updated.
        assertEq(token0.balanceOf(address(merklOperator)), 0);

        // And: Owner should receive the tokens.
        assertEq(token0.balanceOf(users.owner), amount);
    }
}
