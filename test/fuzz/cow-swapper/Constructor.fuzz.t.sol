/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { CowSwapperExtension } from "../../utils/extensions/CowSwapperExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "CowSwapper".
 */
contract Constructor_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address hooksTrampoline) public {
        CowSwapperExtension cowSwapper_ =
            new CowSwapperExtension(owner_, arcadiaFactory, address(flashLoanRouter), hooksTrampoline);

        assertEq(cowSwapper_.owner(), owner_);
        assertEq(address(cowSwapper_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(cowSwapper_.HOOKS_TRAMPOLINE()), hooksTrampoline);
        assertEq(address(cowSwapper_.VAULT_RELAYER()), address(vaultRelayer));
        assertEq(address(cowSwapper_.settlementContract()), address(settlement));
    }
}
