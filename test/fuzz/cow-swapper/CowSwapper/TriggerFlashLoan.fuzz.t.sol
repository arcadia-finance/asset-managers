/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { Guardian } from "../../../../src/guardian/Guardian.sol";
import { IERC20 } from "../../../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { Loan } from "../../../../lib/flash-loan-router/src/library/Loan.sol";
import { LoansWithSettlement } from "../../../../lib/flash-loan-router/src/library/LoansWithSettlement.sol";

/**
 * @notice Fuzz tests for the function "triggerFlashLoan" of contract "CowSwapper".
 */
contract TriggerFlashLoan_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    using LoansWithSettlement for bytes;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_triggerFlashLoan_Paused(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given: CowSwapper is Paused.
        vm.prank(users.owner);
        cowSwapper.setPauseFlag(true);

        // When: calling triggerFlashLoan.
        // Then: it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(Guardian.Paused.selector);
        cowSwapper.triggerFlashLoan_(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_Reentered(
        address account_,
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given: account is not address(0)
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // When: calling triggerFlashLoan.
        // Then: it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.triggerFlashLoan_(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_ZeroAmountIn(
        address account_,
        IERC20 tokenIn,
        bytes calldata callBackData
    ) public {
        // Given: amountIn is zero.
        uint256 amountIn = 0;

        // When: calling triggerFlashLoan.
        // Then: it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        cowSwapper.triggerFlashLoan_(account_, tokenIn, amountIn, callBackData);
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

        // When: calling triggerFlashLoan.
        // Then: it should revert
        vm.prank(address(flashLoanRouter));
        if (!isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        cowSwapper.triggerFlashLoan_(account_, tokenIn, amountIn, callBackData);
    }

    function testFuzz_Revert_triggerFlashLoan_InvalidInitiator(
        IERC20 tokenIn,
        uint256 amountIn,
        bytes calldata callBackData
    ) public {
        // Given: Owner of the account has not set an initiator yet.

        // And: AmountIn is not zero.
        amountIn = bound(amountIn, 1, type(uint256).max);

        // When: calling triggerFlashLoan.
        // Then: it should revert
        vm.prank(address(flashLoanRouter));
        vm.expectRevert(CowSwapper.InvalidInitiator.selector);
        cowSwapper.triggerFlashLoan_(address(account), tokenIn, amountIn, callBackData);
    }

    function testFuzz_Success_triggerFlashLoan(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        uint256 buyClearingPrice,
        uint256 buyAmount
    ) public {
        // Given: Valid initiator.
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Account has sufficient tokenIn balance.
        depositErc20InAccount(account, ERC20Mock(address(order.sellToken)), order.sellAmount);

        // And: Clearing price is better than order demand.
        buyClearingPrice = bound(buyClearingPrice, order.buyAmount + 1, type(uint160).max);
        // And: Slippage is positive
        buyAmount = bound(buyAmount, buyClearingPrice, type(uint160).max);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), buyAmount, true);

        // Get the loansWithSettlement call data.
        bytes memory callBackData;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );

            bytes memory settlementCallData =
                getSettlementCallData(swapFee, order, signature, buyClearingPrice, buyAmount);

            callBackData = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            callBackData.popLoan();
        }

        // And: Transient state is set.
        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(callBackData.hash());

        // When: calling triggerFlashLoan.
        vm.prank(address(flashLoanRouter));
        cowSwapper.triggerFlashLoan_(address(account), IERC20(address(order.sellToken)), order.sellAmount, callBackData);

        // Then: Account is reset.
        assertEq(accountsGuard.getAccount(), address(0));
        assertEq(cowSwapper.getAccount(), address(0));

        // And: Account has received the expected amount of tokenOut.
        uint256 fee = buyClearingPrice * swapFee / 1e18;
        assertEq(order.buyToken.balanceOf(address(account)), buyClearingPrice - fee);

        // And: Initiator has received the expected fee.
        assertEq(order.buyToken.balanceOf(initiator), fee);

        // And: Positive slippage can be pocketed by solver.
        assertEq(order.buyToken.balanceOf(address(settlement)), buyAmount - buyClearingPrice);
    }
}
