/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPriceX96" of contract "RebalancerUniswapV4".
 */
contract GetSqrtPriceX96_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPriceX96(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        bool native
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, native);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getSqrtPriceX96.
        uint160 sqrtPriceX96 = rebalancer.getSqrtPriceX96(position);

        // Then: It should return the correct values.
        (uint160 sqrtPriceX96_,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPriceX96, sqrtPriceX96_);
    }
}
