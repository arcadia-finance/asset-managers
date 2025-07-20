/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { RebalancerExtension } from "../../../../utils/extensions/RebalancerExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Rebalancer".
 */
contract Constructor_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address routerTrampoline_) public {
        RebalancerExtension rebalancer_ = new RebalancerExtension(owner_, arcadiaFactory, routerTrampoline_);

        assertEq(rebalancer_.owner(), owner_);
        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(rebalancer_.ROUTER_TRAMPOLINE()), routerTrampoline_);
    }
}
