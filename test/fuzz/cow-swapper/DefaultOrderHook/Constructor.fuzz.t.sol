/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook_Fuzz_Test } from "./_DefaultOrderHook.fuzz.t.sol";
import { DefaultOrderHookExtension } from "../../../utils/extensions/DefaultOrderHookExtension.sol";
import { LibString } from "../../../../lib/accounts-v2/lib/solady/src/utils/LibString.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "DefaultOrderHook".
 */
contract Constructor_DefaultOrderHook_Fuzz_Test is DefaultOrderHook_Fuzz_Test {
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
    function testFuzz_Success_Constructor() public {
        DefaultOrderHookExtension orderHook_ = new DefaultOrderHookExtension(address(cowSwapper));

        assertEq(orderHook_.COW_SWAPPER(), address(cowSwapper));
        assertEq(orderHook_.getCowSwapperHexString(), LibString.toHexString(address(cowSwapper)));
        assertEq(orderHook_.DOMAIN_SEPARATOR(), settlement.domainSeparator());
    }
}
