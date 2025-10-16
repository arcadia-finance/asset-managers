/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { IERC20 } from "../../../../lib/flash-loan-router/src/vendored/IERC20.sol";

/**
 * @notice Fuzz tests for the function "flashLoanAndCallBack" of contract "CowSwapper/Borrower".
 */
contract FlashLoanAndCallBack_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
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
}
