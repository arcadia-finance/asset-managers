/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalancerUniV3Slipstream } from "../../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RebalancerUniV3Slipstream_Fuzz_Test } from "./_RebalancerUniV3Slipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "RebalancerUniV3Slipstream".
 */
contract Constructor_RebalancerUniV3Slipstream_Fuzz_Test is RebalancerUniV3Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(uint256 maxTolerance, uint256 maxInitiatorFee, uint256 maxSlippageRatio)
        public
    {
        vm.prank(users.owner);
        RebalancerUniV3Slipstream rebalancer_ =
            new RebalancerUniV3Slipstream(maxTolerance, maxInitiatorFee, maxSlippageRatio);

        assertEq(rebalancer_.MAX_TOLERANCE(), maxTolerance);
        assertEq(rebalancer_.MAX_INITIATOR_FEE(), maxInitiatorFee);
        assertEq(rebalancer_.MIN_LIQUIDITY_RATIO(), maxSlippageRatio);
    }
}
