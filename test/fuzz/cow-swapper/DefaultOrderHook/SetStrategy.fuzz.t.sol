/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook } from "../../../../src/cow-swapper/periphery/DefaultOrderHook.sol";
import { DefaultOrderHook_Fuzz_Test } from "./_DefaultOrderHook.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setHook" of contract "DefaultOrderHook".
 */
contract SetHook_DefaultOrderHook_Fuzz_Test is DefaultOrderHook_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(DefaultOrderHook_Fuzz_Test) {
        DefaultOrderHook_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_setHook(
        address rebalancer,
        address account_,
        DefaultOrderHook.AccountInfo memory accountInfo
    ) public {
        // Given: hook is deployed.

        // When: CoW Swapper sets strategy.
        bytes memory hookData = abi.encode(accountInfo.customInfo);
        vm.prank(rebalancer);
        orderHook.setHook(account_, hookData);

        // Then: Account info should be set for Account.
        bytes memory customInfo = orderHook.accountInfo(rebalancer, account_);
        assertEq(accountInfo.customInfo, customInfo);
    }
}
