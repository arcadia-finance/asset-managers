/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPrice" of contract "RebalancerUniswapV3".
 */
contract GetSqrtPrice_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPrice(uint128 liquidityPool, Rebalancer.PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getSqrtPrice.
        uint160 sqrtPrice = rebalancer.getSqrtPrice(position);

        // Then: It should return the correct values.
        (uint160 sqrtPrice_,,,,,,) = poolUniswap.slot0();
        assertEq(sqrtPrice, sqrtPrice_);
    }
}
