/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPoolLiquidity" of contract "RebalancerUniswapV4".
 */
contract GetPoolLiquidity_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPoolLiquidity(uint128 liquidityPool, PositionState memory position, bool native)
        public
    {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, native);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPoolLiquidity.
        uint128 liquidity = rebalancer.getPoolLiquidity(position);

        // Then: It should return the correct values.
        assertEq(liquidity, stateView.getLiquidity(poolKey.toId()));
    }
}
