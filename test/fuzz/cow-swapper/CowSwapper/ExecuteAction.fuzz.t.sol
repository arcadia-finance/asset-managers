/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { ICowSettlement } from "../../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { LibString } from "../../../../lib/accounts-v2/lib/solady/src/utils/LibString.sol";
import { Loan } from "../../../../lib/flash-loan-router/src/library/Loan.sol";
import { LoansWithSettlement } from "../../../../lib/flash-loan-router/src/library/LoansWithSettlement.sol";
import { MaliciousSolver } from "../../../utils/mocks/MaliciousSolver.sol";

/**
 * @notice Fuzz tests for the function "executeAction" of contract "CowSwapper".
 */
contract ExecuteAction_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    using LibString for string;
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
    function testFuzz_Revert_executeAction_OnlyAccount(address account_, bytes calldata callBackData, address caller)
        public
    {
        // Given : Caller is not the account.
        vm.assume(caller != account_);

        // And: account is set.
        cowSwapper.setAccount(account_);

        // When : calling executeAction.
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(CowSwapper.OnlyAccount.selector);
        cowSwapper.executeAction(callBackData);
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order
    ) public {
        // Given: Valid initiator.
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Invalid swap fee.
        swapFee = uint64(bound(swapFee, MAX_FEE + 1, type(uint64).max));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // Get the loansWithSettlement call data.
        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);
            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_ReplayedSignature(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // Get the loansWithSettlement call data.
        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);
            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // And: Swap is Successfully executed.
        vm.prank(address(account));
        cowSwapper.executeAction(loansWithSettlement);

        // And: Signature is replayed.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);
        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_MissingBeforeSwap(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );
            (
                address[] memory tokens,
                uint256[] memory clearingPrices,
                ICowSettlement.Trade[] memory trades,
                ICowSettlement.Interaction[][3] memory interactions
            ) = getSettlementData(swapFee, order, signature);
            // And: The beforeSwap hook is not called.
            // Remove the hooks interaction.
            interactions[0] = new ICowSettlement.Interaction[](0);
            bytes memory settlementCallData =
                abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InvalidOrderHash(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes32 invalidAppDataHash
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );

            // And: Order hash is not correct.
            vm.assume(invalidAppDataHash != order.appData);
            order.appData = invalidAppDataHash;
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_ReplacedAccount(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        address account_
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            // And: Account is replaced by solver.
            vm.assume(account_ != address(account));
            bytes memory signature =
                abi.encodePacked(address(cowSwapper), getSignature(account_, swapFee, order, initiatorPrivateKey));
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_ReplacedSwapFee(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        uint64 swapFee_
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            // And: SwapFee is replaced by solver.
            vm.assume(swapFee_ != swapFee);
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee_, order, initiatorPrivateKey)
            );
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InvalidSignatureLength(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes calldata invalidSignature
    ) public {
        vm.assume(invalidSignature.length != 65 && invalidSignature.length != 64);

        // Given: Valid initiator.
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            // And: The signature length is not correct.
            bytes memory signature = abi.encodePacked(address(cowSwapper), invalidSignature);
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InvalidSignature(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes32 r,
        bytes32 s,
        bytes1 invalidV
    ) public {
        vm.assume(invalidV != bytes1(uint8(27)) && invalidV != bytes1(uint8(28)));

        // Given: Valid initiator.
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            // And: The signature is not valid.
            bytes memory invalidSignature = new bytes(65);
            assembly {
                mstore(add(invalidSignature, 32), r)
                mstore(add(invalidSignature, 64), s)
                mstore8(add(invalidSignature, 96), invalidV)
            }
            bytes memory signature = abi.encodePacked(address(cowSwapper), invalidSignature);
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InvalidInitiator(
        uint256 signerPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        address initiator
    ) public {
        // Given: Valid signer.
        signerPrivateKey = givenValidPrivatekey(signerPrivateKey);

        // And: Signer is not the initiator.
        vm.assume(initiator != vm.addr(signerPrivateKey));

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            // And: The signer is not the initiator.
            bytes memory signature =
                abi.encodePacked(address(cowSwapper), getSignature(address(account), swapFee, order, signerPrivateKey));
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_MissingIsValidSignature(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: isValidSignature() is called on a malicious contract, replaced by a malicious solver.
        bytes memory loansWithSettlement;
        {
            MaliciousSolver maliciousSolver = new MaliciousSolver();
            maliciousSolver.approve(address(order.sellToken), address(vaultRelayer), order.sellAmount);
            deal(address(order.sellToken), address(maliciousSolver), order.sellAmount, true);
            bytes memory signature = abi.encodePacked(address(maliciousSolver), bytes(""));
            bytes memory settlementCallData = getSettlementCallData(swapFee, order, signature);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert(CowSwapper.MissingSignatureVerification.selector);
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_MissingIsValidSignatureAndMissingBeforeSwap(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: isValidSignature() is called on a malicious contract, replaced by a malicious solver.
        bytes memory loansWithSettlement;
        {
            MaliciousSolver maliciousSolver = new MaliciousSolver();
            maliciousSolver.approve(address(order.sellToken), address(vaultRelayer), order.sellAmount);
            deal(address(order.sellToken), address(maliciousSolver), order.sellAmount, true);
            bytes memory signature = abi.encodePacked(address(maliciousSolver), bytes(""));
            (
                address[] memory tokens,
                uint256[] memory clearingPrices,
                ICowSettlement.Trade[] memory trades,
                ICowSettlement.Interaction[][3] memory interactions
            ) = getSettlementData(swapFee, order, signature);
            // Remove the hooks interaction.
            interactions[0] = new ICowSettlement.Interaction[](0);
            bytes memory settlementCallData =
                abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert(CowSwapper.MissingSignatureVerification.selector);
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InsufficientClearingPrice(
        uint256 initiatorPrivateKey,
        uint64 swapFee,
        GPv2Order.Data memory order,
        uint256 buyClearingPrice
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Clearing price is worse than order demand.
        buyClearingPrice = bound(buyClearingPrice, 0, order.buyAmount - 1);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );

            bytes memory settlementCallData =
                getSettlementCallData(swapFee, order, signature, buyClearingPrice, order.buyAmount);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Revert_executeAction_InsufficientBuyToken(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Slippage is negative.
        buyAmount = bound(buyAmount, 0, order.buyAmount - 1);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), buyAmount, true);

        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );

            bytes memory settlementCallData =
                getSettlementCallData(swapFee, order, signature, order.buyAmount, buyAmount);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        // Then: it should revert.
        vm.prank(address(account));
        vm.expectRevert("Settlement reverted");
        cowSwapper.executeAction(loansWithSettlement);
    }

    function testFuzz_Success_executeAction(
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

        // And: Cow Swapper has balance sellToken.
        deal(address(order.sellToken), address(cowSwapper), order.sellAmount, true);

        // And: Clearing price is better than order demand.
        buyClearingPrice = bound(buyClearingPrice, order.buyAmount + 1, type(uint160).max);
        // And: Slippage is positive
        buyAmount = bound(buyAmount, buyClearingPrice, type(uint160).max);

        // And: Router can execute the swap.
        deal(address(order.buyToken), address(routerMock), buyAmount, true);

        // Get the loansWithSettlement call data.
        bytes memory loansWithSettlement;
        {
            bytes memory signature = abi.encodePacked(
                address(cowSwapper), getSignature(address(account), swapFee, order, initiatorPrivateKey)
            );

            bytes memory settlementCallData =
                getSettlementCallData(swapFee, order, signature, buyClearingPrice, buyAmount);

            loansWithSettlement = this.getLoansWithSettlement(new Loan.Data[](1), settlementCallData);
            loansWithSettlement.popLoan();
        }

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        flashLoanRouter.setPendingBorrower(address(cowSwapper));
        flashLoanRouter.setPendingDataHash(loansWithSettlement.hash());

        // When: Account calls executeAction.
        vm.prank(address(account));
        ActionData memory depositData = cowSwapper.executeAction(loansWithSettlement);

        // Then: Initiator has received the expected fee.
        uint256 fee = uint256(buyClearingPrice) * swapFee / 1e18;
        assertEq(order.buyToken.balanceOf(initiator), fee);

        // And: Return data should be correct.
        assertEq(depositData.assetTypes[0], 1);
        assertEq(depositData.assetIds[0], 0);
        assertEq(depositData.assetAmounts[0], buyClearingPrice - fee);
        assertEq(depositData.assets[0], address(order.buyToken));

        // And: Approval should be set.
        assertEq(order.buyToken.allowance(address(cowSwapper), address(account)), buyClearingPrice - fee);

        // And: Positive slippage can be pocketed by solver.
        assertEq(order.buyToken.balanceOf(address(settlement)), buyAmount - buyClearingPrice);
    }
}
