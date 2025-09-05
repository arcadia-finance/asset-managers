/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { CompounderExtension } from "../../../../utils/extensions/CompounderExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Compounder".
 */
contract Constructor_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        CompounderExtension compounder_ = new CompounderExtension(owner_, arcadiaFactory, routerTrampoline_);

        assertEq(compounder_.owner(), owner_);
        assertEq(address(compounder_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(compounder_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
