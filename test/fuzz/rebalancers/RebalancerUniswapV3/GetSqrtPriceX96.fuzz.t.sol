/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPriceX96" of contract "RebalancerUniswapV3".
 */
contract GetSqrtPriceX96_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPriceX96(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position
    ) public {
        // Given: A valid position.
        givenValidPosition(liquidityPool, initiatorParams, position);

        // When: Calling getSqrtPriceX96.
        uint160 sqrtPriceX96 = rebalancer.getSqrtPriceX96(position);

        // Then: It should return the correct values.
        (uint160 sqrtPriceX96_,,,,,,) = poolUniswap.slot0();
        assertEq(sqrtPriceX96, sqrtPriceX96_);
    }
}
