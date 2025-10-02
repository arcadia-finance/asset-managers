/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { CowSwapper } from "../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { ICowSettlement } from "../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { LibString } from "../../../lib/accounts-v2/lib/solady/src/utils/LibString.sol";
import { Loan } from "../../../lib/flash-loan-router/src/library/Loan.sol";
import { LoansWithSettlement } from "../../../lib/flash-loan-router/src/library/LoansWithSettlement.sol";

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

        // And: The beforeSwap hook is not called.
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

    function testFuzz_Success_executeAction(uint256 initiatorPrivateKey, uint64 swapFee, GPv2Order.Data memory order)
        public
    {
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

        // When: Account calls executeAction.
        vm.prank(address(account));
        ActionData memory depositData = cowSwapper.executeAction(loansWithSettlement);

        // Then: Initiator has received the expected fee.
        uint256 fee = uint256(order.buyAmount) * swapFee / 1e18;
        assertEq(order.buyToken.balanceOf(initiator), fee);

        // And: Return data should be correct.
        assertEq(depositData.assetTypes[0], 1);
        assertEq(depositData.assetIds[0], 0);
        assertEq(depositData.assetAmounts[0], order.buyAmount - fee);
        assertEq(depositData.assets[0], address(order.buyToken));

        // And: Approval should be set.
        assertEq(order.buyToken.allowance(address(cowSwapper), address(account)), order.buyAmount - fee);
    }

    function getLoansWithSettlement(Loan.Data[] calldata loans, bytes calldata settlementCallData)
        public
        pure
        returns (bytes memory)
    {
        return LoansWithSettlement.encode(loans, settlementCallData);
    }

    function getAppDataHash(
        address account_,
        address cowSwapper,
        address tokenIn,
        uint256 amountIn,
        bytes memory callData_
    ) internal pure returns (bytes32 appDataHash) {
        appDataHash = keccak256(
            bytes(
                string.concat(
                    '{"appCode":"Arcadia 0.1.0","metadata":{"flashloan":{"amount":"',
                    LibString.toString(amountIn),
                    '","borrower":"',
                    LibString.toHexString(cowSwapper),
                    '","lender":"',
                    LibString.toHexString(account_),
                    '","token":"',
                    LibString.toHexString(tokenIn),
                    '"},"hooks":{"pre":[{"callData":"',
                    LibString.toHexString(callData_),
                    '","gasLimit":"80000","target":"',
                    LibString.toHexString(cowSwapper),
                    '"}],"version":"0.1.0"},"quote":{"slippageBips":100}},"version":"1.6.0"}'
                )
            )
        );
    }

    function test_appDataHash() public {
        emit log_bytes32(
            getAppDataHash(
                0x426981eC47Ca15c15C800430754B459b62C14410,
                0x426981eC47Ca15c15C800430754B459b62C14410,
                0x426981eC47Ca15c15C800430754B459b62C14410,
                1,
                hex"00"
            )
        );
    }
}
