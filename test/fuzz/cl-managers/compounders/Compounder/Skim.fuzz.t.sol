/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { RevertingReceive } from "../../../../../lib/accounts-v2/test/utils/mocks/RevertingReceive.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "Compounder".
 */
contract Skim_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_skim_NonOwner(address nonOwner, address token) public {
        // Given: Non-owner is not the owner of the compounder.
        vm.assume(nonOwner != users.owner);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        compounder.skim(token);
    }

    function testFuzz_Revert_skim_Paused(address token) public {
        // Given : compounder is Paused.
        vm.prank(users.owner);
        compounder.setPauseFlag(true);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Guardian.Paused.selector);
        compounder.skim(token);
    }

    function testFuzz_Revert_compound_Reentered(address account_, address token) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.skim(token);
    }

    function testFuzz_Revert_skim_NativeToken_Receive(uint256 amount) public {
        // Given: Owner cannot receive native tokens.
        RevertingReceive revertingReceiver = new RevertingReceive();
        vm.prank(users.owner);
        compounder.transferOwnership(address(revertingReceiver));

        // And: meklOperator has a native token balance.
        uint256 balancePre = address(revertingReceiver).balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(revertingReceiver), amount);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(address(revertingReceiver));
        vm.expectRevert(RevertingReceive.TestError.selector);
        compounder.skim(address(0));
    }

    function testFuzz_Success_skim_Ether(uint256 amount) public {
        // Given: meklOperator has a native token balance.
        uint256 balancePre = users.owner.balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(compounder), amount);

        // When: Calling skim.
        vm.prank(users.owner);
        compounder.skim(address(0));

        // Then: The balance of the compounder should be updated.
        assertEq(address(compounder).balance, 0);

        // And: Owner should receive the tokens.
        assertEq(users.owner.balance, balancePre + amount);
    }

    function testFuzz_Success_skim_ERC20(uint256 amount) public {
        // Given: meklOperator has an ERC20 balance.
        deal(address(token0), address(compounder), amount, true);

        // When: Calling skim.
        vm.prank(users.owner);
        compounder.skim(address(token0));

        // Then: The balance of the compounder should be updated.
        assertEq(token0.balanceOf(address(compounder)), 0);

        // And: Owner should receive the tokens.
        assertEq(token0.balanceOf(users.owner), amount);
    }
}
