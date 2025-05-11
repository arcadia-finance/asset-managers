/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getUnderlyingTokens" of contract "RebalancerUniswapV4".
 */
contract GetUnderlyingTokens_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getUnderlyingTokens_NotNative(uint128 liquidityPool, PositionState memory position)
        public
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        (address token0_, address token1_) = rebalancer.getUnderlyingTokens(address(positionManagerV4), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(token0));
        assertEq(token1_, address(token1));
    }

    function testFuzz_Success_getUnderlyingTokens_IsNative(uint128 liquidityPool, PositionState memory position)
        public
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        (address token0_, address token1_) = rebalancer.getUnderlyingTokens(address(positionManagerV4), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(weth9));
        assertEq(token1_, address(token1));
    }
}
