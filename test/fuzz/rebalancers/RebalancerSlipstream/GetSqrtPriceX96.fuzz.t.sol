/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPrice" of contract "RebalancerSlipstream".
 */
contract GetSqrtPrice_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPrice(uint128 liquidityPool, Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getSqrtPrice.
        uint160 sqrtPrice = rebalancer.getSqrtPrice(position);

        // Then: It should return the correct values.
        (uint160 sqrtPrice_,,,,,) = poolCl.slot0();
        assertEq(sqrtPrice, sqrtPrice_);
    }
}
