/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountsGuard } from "../../../../lib/accounts-v2/src/accounts/helpers/AccountsGuard.sol";
import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { Guardian } from "../../../../src/guardian/Guardian.sol";
import { IBorrower } from "../../../../lib/flash-loan-router/src/interface/IBorrower.sol";
import { ICowSettlement } from "../../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { IERC20 } from "../../../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { Loan } from "../../../../lib/flash-loan-router/src/library/Loan.sol";
import { MaliciousSolver } from "../../../utils/mocks/MaliciousSolver.sol";

/**
 * @notice Fuzz tests for the function full "flashLoanAndSettle" flow of contract "CowSwapper".
 */
contract EndToEnd_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_EndToEnd_Paused(Loan.Data memory loan, bytes calldata settlementCallData) public {
        // Given : CowSwapper is Paused.
        vm.prank(users.owner);
        cowSwapper.setPauseFlag(true);

        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(Guardian.Paused.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_CowSwapperReentered(
        Loan.Data memory loan,
        bytes calldata settlementCallData,
        address account_
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(CowSwapper.Reentered.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_ZeroAmountIn(Loan.Data memory loan, bytes calldata settlementCallData) public {
        // Given: amountIn is zero.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));
        loan.amount = 0;

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InvalidAccount(
        Loan.Data memory loan,
        bytes calldata settlementCallData,
        address account_
    ) public {
        // Given: amountIn is not zero.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));
        loan.amount = bound(loan.amount, 1, type(uint256).max);

        // And: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));
        loan.lender = account_;

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        if (!isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InvalidInitiator(Loan.Data memory loan, bytes calldata settlementCallData)
        public
    {
        // Given: amountIn is not zero.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));
        loan.amount = bound(loan.amount, 1, type(uint256).max);
        loan.lender = address(account);

        // And: No initiator is set.

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(CowSwapper.InvalidInitiator.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_AccountGuardReentered(
        Loan.Data memory loan,
        bytes calldata settlementCallData,
        address account_,
        address initiator
    ) public {
        // Given: amountIn is not zero.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loan;
        loan.borrower = IBorrower(address(cowSwapper));
        loan.amount = bound(loan.amount, 1, type(uint256).max);
        loan.lender = address(account);

        // And: Cow swapper is set as asset manager with initiator.
        vm.assume(initiator != address(0));
        setCowSwapper(initiator);

        // And: account is not address(0)
        vm.assume(account_ != address(0));
        accountsGuard.setAccount(account_);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(AccountsGuard.Reentered.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_revert_EndToEnd_ReplayedSignature(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: Valid EIP-1271 signature.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey));

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

        // And: Swap is Successfully executed.
        vm.prank(solver);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);

        // And: Signature is replayed.
        depositErc20InAccount(account, ERC20Mock(address(order.sellToken)), order.sellAmount);
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_MissingBeforeSwap(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order
    ) public {
        // Given: Valid signer.
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: Valid EIP-1271 signature.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey));

        // And: The beforeSwap hook is not called.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData;
        {
            (
                address[] memory tokens,
                uint256[] memory clearingPrices,
                ICowSettlement.Trade[] memory trades,
                ICowSettlement.Interaction[][3] memory interactions
            ) = getSettlementData(swapFee, order, signature);
            // Remove the hooks interaction.
            interactions[0] = new ICowSettlement.Interaction[](0);
            settlementCallData = abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));
        }

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InvalidOrderHash(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes32 invalidAppDataHash
    ) public {
        // Given: Valid signer.
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: Valid EIP-1271 signature.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey));

        // And: Order hash is not correct.
        vm.assume(invalidAppDataHash != order.appData);
        order.appData = invalidAppDataHash;
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_ReplacedAccount(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        address account_
    ) public {
        // Given: Valid signer.
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: Account is replaced by solver.
        vm.assume(account_ != address(account));
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(account_, swapFee, order, initiatorPrivateKey));

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InvalidSignature(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes32 r,
        bytes32 s,
        bytes1 invalidV
    ) public {
        // Given: Valid signer.
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: The signature is not valid.
        bytes memory invalidSignature = new bytes(65);
        assembly {
            mstore(add(invalidSignature, 32), r)
            mstore(add(invalidSignature, 64), s)
            mstore8(add(invalidSignature, 96), invalidV)
        }

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, invalidSignature);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InvalidSigner(
        uint256 signerPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        address initiator
    ) public {
        // Given: Valid signer.
        signerPrivateKey = givenValidPrivatekey(signerPrivateKey);

        // And: Signer is not the initiator.
        vm.assume(initiator != vm.addr(signerPrivateKey));
        vm.assume(initiator != address(0));

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Account has sufficient tokenIn balance.
        depositErc20InAccount(account, ERC20Mock(address(order.sellToken)), order.sellAmount);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: The signer is not the initiator.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, signerPrivateKey));

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_MissingIsValidSignature(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order
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

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: isValidSignature() is called on a malicious contract, replaced by a malicious solver.
        MaliciousSolver maliciousSolver = new MaliciousSolver();
        maliciousSolver.approve(address(order.sellToken), address(vaultRelayer), order.sellAmount);
        deal(address(order.sellToken), address(maliciousSolver), order.sellAmount, true);
        bytes memory signature = abi.encodePacked(address(maliciousSolver), bytes(""));

        // And: Solver processes the malicious order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert(CowSwapper.MissingSignatureVerification.selector);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Revert_EndToEnd_InsufficientBuyToken(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
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

        // And: Slippage is negative.
        buyAmount = bound(buyAmount, 0, order.buyAmount - 1);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), buyAmount, true);

        // And: Valid EIP-1271 signature.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey));

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature, order.buyAmount, buyAmount);

        // When: The solver calls the flash loan router.
        // Then: it should revert.
        vm.prank(solver);
        vm.expectRevert("Settlement reverted");
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);
    }

    function testFuzz_Success_EndToEnd_Initiator(
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

        // And: Valid EIP-1271 signature.
        bytes memory signature =
            abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey));

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature, buyClearingPrice, buyAmount);

        // When: The solver calls the flash loan router.
        vm.prank(solver);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);

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

    function testFuzz_Success_EndToEnd_Initiator(
        uint256 accountOwnerPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        uint256 buyClearingPrice,
        uint256 buyAmount,
        address initiator
    ) public {
        // Given: Valid Account owner.
        accountOwnerPrivateKey = givenValidPrivatekey(accountOwnerPrivateKey);
        address accountOwner = vm.addr(accountOwnerPrivateKey);
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, accountOwner, address(account));

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        vm.assume(initiator != address(0));
        setCowSwapper(initiator);

        // And: Account has sufficient tokenIn balance.
        depositErc20InAccount(account, ERC20Mock(address(order.sellToken)), order.sellAmount);

        // And: Clearing price is better than order demand.
        buyClearingPrice = bound(buyClearingPrice, order.buyAmount + 1, type(uint160).max);
        // And: Slippage is positive
        buyAmount = bound(buyAmount, buyClearingPrice, type(uint160).max);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), buyAmount, true);

        // And: Valid EIP-1271 signature.
        bytes memory signature = abi.encodePacked(
            address(cowSwapper), getSignature(address(account), swapFee, order, accountOwnerPrivateKey)
        );

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });
        bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature, buyClearingPrice, buyAmount);

        // When: The solver calls the flash loan router.
        vm.prank(solver);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);

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
