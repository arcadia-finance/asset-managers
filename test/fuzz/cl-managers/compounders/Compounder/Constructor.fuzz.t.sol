/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

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
    function testFuzz_Success_Constructor(address arcadiaFactory, address routerTrampoline_) public {
        vm.prank(users.owner);
        CompounderExtension compounder_ = new CompounderExtension(arcadiaFactory, routerTrampoline_);

        assertEq(address(compounder_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(compounder_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
