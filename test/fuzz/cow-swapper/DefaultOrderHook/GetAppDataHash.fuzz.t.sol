/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook_Fuzz_Test } from "./_DefaultOrderHook.fuzz.t.sol";
import { LibString } from "../../../../lib/accounts-v2/lib/solady/src/utils/LibString.sol";

/**
 * @notice Fuzz tests for the function "getAppDataHash" of contract "DefaultOrderHook".
 */
contract GetAppDataHash_DefaultOrderHook_Fuzz_Test is DefaultOrderHook_Fuzz_Test {
    using LibString for string;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        DefaultOrderHook_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAppDataHash() public view {
        // Given: fixed values.
        bytes memory beforeSwapCallData = hex"00";

        // When: getAppDataHash is called.
        bytes32 appDataHash = orderHook.getAppDataHash(
            0x426981eC47Ca15c15C800430754B459b62C14410,
            0x426981eC47Ca15c15C800430754B459b62C14410,
            1,
            beforeSwapCallData
        );

        // Then: It should match the hash calculated with https://explorer.cow.fi/appdata?tab=encode.
        // AppData JSON: {"appCode":"Arcadia 0.1.0","metadata":{"flashloan":{"amount":"1","borrower":"0xc7183455a4c133ae270771860664b6b7ec320bb1","lender":"0x426981ec47ca15c15c800430754b459b62c14410","token":"0x426981ec47ca15c15c800430754b459b62c14410"},"hooks":{"pre":[{"callData":"0x00","gasLimit":"80000","target":"0xc7183455a4c133ae270771860664b6b7ec320bb1"}],"version":"0.1.0"},"quote":{"slippageBips":100}},"version":"1.6.0"}
        assertEq(appDataHash, 0x4eb78053eac0de75d2b1631e24ffc645fcf00ec36136bb130f5e9ac6ce62ae2e);
    }
}
