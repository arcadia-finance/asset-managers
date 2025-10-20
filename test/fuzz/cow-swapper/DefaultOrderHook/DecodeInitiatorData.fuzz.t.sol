/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook_Fuzz_Test } from "./_DefaultOrderHook.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_decodeInitiatorData" of contract "DefaultOrderHook".
 */
contract DecodeInitiatorData_DefaultOrderHook_Fuzz_Test is DefaultOrderHook_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(DefaultOrderHook_Fuzz_Test) {
        DefaultOrderHook_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_decodeInitiatorData(address tokenOut, uint112 amountOut, uint32 validTo, uint64 swapFee)
        public
        view
    {
        // Given: hook is deployed.
        bytes memory initiatorData = abi.encodePacked(tokenOut, amountOut, validTo, swapFee);

        // When: decodeInitiatorData is called.
        (address tokenOut_, uint112 amountOut_, uint32 validTo_, uint64 swapFee_) =
            orderHook.decodeInitiatorData(initiatorData);

        // Then: Correct values should be returned.
        assertEq(tokenOut_, tokenOut);
        assertEq(amountOut_, amountOut);
        assertEq(validTo_, validTo);
        assertEq(swapFee_, swapFee);
    }
}
