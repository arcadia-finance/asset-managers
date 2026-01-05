/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { RevertingReceive } from "../../../../../lib/accounts-v2/test/utils/mocks/RevertingReceive.sol";

/**
 * @notice Fuzz tests for the function "skim" of contract "Closer".
 */
contract Skim_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_skim_NonOwner(address nonOwner, address token) public {
        // Given: Non-owner is not the owner of the closer.
        vm.assume(nonOwner != users.owner);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(nonOwner);
        vm.expectRevert("UNAUTHORIZED");
        closer.skim(token);
    }

    function testFuzz_Revert_skim_Paused(address token) public {
        // Given: closer is Paused.
        vm.prank(users.owner);
        closer.setPauseFlag(true);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Guardian.Paused.selector);
        closer.skim(token);
    }

    function testFuzz_Revert_skim_Reentered(address account_, address token) public {
        // Given: account is not address(0)
        vm.assume(account_ != address(0));
        closer.setAccount(account_);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(users.owner);
        vm.expectRevert(Closer.Reentered.selector);
        closer.skim(token);
    }

    function testFuzz_Revert_skim_NativeToken_Receive(uint256 amount) public {
        // Given: Owner cannot receive native tokens.
        RevertingReceive revertingReceiver = new RevertingReceive();
        vm.prank(users.owner);
        closer.transferOwnership(address(revertingReceiver));

        // And: merklOperator has a native token balance.
        uint256 balancePre = address(revertingReceiver).balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(revertingReceiver), amount);

        // When: Calling skim.
        // Then: It should revert.
        vm.prank(address(revertingReceiver));
        vm.expectRevert(RevertingReceive.TestError.selector);
        closer.skim(address(0));
    }

    function testFuzz_Success_skim_NativeToken(uint256 amount) public {
        // Given: closer has a native token balance.
        uint256 balancePre = users.owner.balance;
        amount = bound(amount, 0, type(uint256).max - balancePre);
        vm.deal(address(closer), amount);

        // When: Calling skim.
        vm.prank(users.owner);
        closer.skim(address(0));

        // Then: The balance of the closer should be updated.
        assertEq(address(closer).balance, 0);

        // And: Owner should receive the tokens.
        assertEq(users.owner.balance, balancePre + amount);
    }

    function testFuzz_Success_skim_ERC20(uint256 amount) public {
        // Given: closer has an ERC20 balance.
        deal(address(token0), address(closer), amount, true);

        // When: Calling skim.
        vm.prank(users.owner);
        closer.skim(address(token0));

        // Then: The balance of the closer should be updated.
        assertEq(token0.balanceOf(address(closer)), 0);

        // And: Owner should receive the tokens.
        assertEq(token0.balanceOf(users.owner), amount);
    }
}
