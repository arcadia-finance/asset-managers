/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getUnderlyingTokens" of contract "RebalancerSlipstream".
 */
contract GetUnderlyingTokens_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getUnderlyingTokens_Slipstream(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position
    ) public {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        (address token0_, address token1_) =
            rebalancer.getUnderlyingTokens(address(slipstreamPositionManager), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(token0));
        assertEq(token1_, address(token1));
    }
}
