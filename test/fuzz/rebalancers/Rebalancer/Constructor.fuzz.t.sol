/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { RebalancerExtension } from "../../../utils/extensions/RebalancerExtension.sol";

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
    function testFuzz_Success_Constructor(address arcadiaFactory) public {
        vm.prank(users.owner);
        RebalancerExtension rebalancer_ = new RebalancerExtension(arcadiaFactory);

        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
    }
}
