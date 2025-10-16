/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook_Fuzz_Test } from "./_DefaultOrderHook.fuzz.t.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";

/**
 * @notice Fuzz tests for the function "getInitiatorParams" of contract "DefaultOrderHook".
 */
contract GetInitiatorParams_DefaultOrderHook_Fuzz_Test is DefaultOrderHook_Fuzz_Test {
    using GPv2Order for GPv2Order.Data;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(DefaultOrderHook_Fuzz_Test) {
        DefaultOrderHook_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getInitiatorParams(address account_, uint64 swapFee, GPv2Order.Data memory order)
        public
        view
    {
        // Given: order is valid.
        order.receiver = address(cowSwapper);
        order.feeAmount = 0;
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = false;
        order.sellTokenBalance = GPv2Order.BALANCE_ERC20;
        order.buyTokenBalance = GPv2Order.BALANCE_ERC20;
        order.appData = getAppDataHash(account_, swapFee, order);

        // And: buyAmount does not exceed type(uint112).max.
        order.buyAmount = uint112(bound(order.buyAmount, 0, type(uint112).max));

        // When: getInitiatorParams is called.
        bytes memory initiatorData = abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee);
        (uint64 swapFee_, address tokenOut, uint256 amountOut, bytes32 orderHash) =
            orderHook.getInitiatorParams(account_, address(order.sellToken), order.sellAmount, initiatorData);

        // Then: Correct values should be returned.
        assertEq(swapFee_, swapFee);
        assertEq(tokenOut, address(order.buyToken));
        assertEq(amountOut, order.buyAmount);
        assertEq(orderHash, order.hash(orderHook.DOMAIN_SEPARATOR()));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function getAppDataHash(address account_, uint64 swapFee, GPv2Order.Data memory order)
        internal
        view
        returns (bytes32 appDataHash)
    {
        bytes memory initiatorData = abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee);
        bytes memory beforeSwapCallData = abi.encodeCall(cowSwapper.beforeSwap, (initiatorData));

        appDataHash = orderHook.getAppDataHash(account_, address(order.sellToken), order.sellAmount, beforeSwapCallData);
    }
}
