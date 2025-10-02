/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { Guardian } from "../../../src/guardian/Guardian.sol";
import { IERC20 } from "../../../lib/flash-loan-router/src/vendored/IERC20.sol";

/**
 * @notice Fuzz tests for the function "triggerFlashLoan" of contract "CowSwapper".
 */
contract TriggerFlashLoan_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_triggerFlashLoan_OnlyRouter(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData,
        address caller
    ) public {
        // Given : Caller is not the Flashloan Router.
        vm.assume(caller != address(flashLoanRouter));

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert("Not the router");
        cowSwapper.flashLoanAndCallBack(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_Paused(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given : CowSwapper is Paused.
        vm.prank(users.owner);
        cowSwapper.setPauseFlag(true);

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(Guardian.Paused.selector);
        cowSwapper.flashLoanAndCallBack(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_Reentered(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.flashLoanAndCallBack(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_ZeroAmountIn(
        address account_,
        IERC20 tokenIn,
        bytes calldata callBackData
    ) public {
        // Given : amountIn is zero.
        uint256 amountIn = 0;

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        cowSwapper.flashLoanAndCallBack(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_InvalidAccount(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));

        // And: AmountIn is not zero.
        amountIn = bound(amountIn, 1, type(uint256).max);

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(address(flashLoanRouter));
        if (!isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        cowSwapper.flashLoanAndCallBack(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_InvalidInitiator(
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given: Owner of the account has not set an initiator yet.

        // And: AmountIn is not zero.
        amountIn = bound(amountIn, 1, type(uint256).max);

        // When : calling triggerFlashLoan.
        // Then : it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.InvalidInitiator.selector);
        cowSwapper.flashLoanAndCallBack(address(account), tokenIn, amountIn, callBackData);
    }
}
