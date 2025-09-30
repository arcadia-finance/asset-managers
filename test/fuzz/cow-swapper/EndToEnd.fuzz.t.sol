/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Borrower } from "../../../src/cow-swapper/vendored/Borrower.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { ERC20Mock } from "../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { HooksTrampoline } from "../../utils/mocks/HooksTrampoline.sol";
import { IBorrower } from "../../../lib/flash-loan-router/src/interface/IBorrower.sol";
import { ICowSettlement } from "../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { IERC20 } from "../../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { Loan } from "../../../lib/flash-loan-router/src/library/Loan.sol";

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
    function testFuzz_Revert_EndToEnd_Paused(
        address account_,
        uint64 swapFee,
        GPv2Order.Data memory order,
        address caller
    ) public { }

    function testFuzz_Success_EndToEnd(uint256 initiatorPrivateKey, uint64 swapFee, GPv2Order.Data memory order)
        public
    {
        // Given: Valid initiator..
        initiatorPrivateKey = givenValidPrivatekey(initiatorPrivateKey);
        address initiator = vm.addr(initiatorPrivateKey);

        // And: Valid swap fee.
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        // And: Valid order.
        givenValidOrder(order);

        // And: Valid beforeSwap signature.
        bytes memory initiatorSignature = getSignature(address(account), swapFee, order, initiatorPrivateKey);

        // And: Valid EIP-1271 signature.
        bytes memory eip1271Signature = abi.encodePacked(address(cowSwapper), bytes(""));

        // And: Cow swapper is set as asset manager with initiator.
        setCowSwapper(initiator);

        // And: Account has sufficient tokenIn balance.
        depositErc20InAccount(account, ERC20Mock(address(order.sellToken)), order.sellAmount);

        // And: Router can successfully execute the swap.
        deal(address(order.buyToken), address(routerMock), order.buyAmount, true);

        // And: Solver correctly processes the order.
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: order.sellAmount,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(order.sellToken))
        });

        bytes memory settlementCallData = getSettlementCallData(swapFee, order, initiatorSignature, eip1271Signature);

        // When: The solver calls the flash loan router.
        vm.prank(solver);
        flashLoanRouter.flashLoanAndSettle(loans, settlementCallData);

        // Then: Account has received the expected amount of tokenOut.
        uint256 fee = uint256(order.buyAmount) * swapFee / 1e18;
        assertEq(order.buyToken.balanceOf(address(account)), order.buyAmount - fee);

        // And: Initiator has received the expected fee.
        assertEq(order.buyToken.balanceOf(initiator), fee);
    }
}
