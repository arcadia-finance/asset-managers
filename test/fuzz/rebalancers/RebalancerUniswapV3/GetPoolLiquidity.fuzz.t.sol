/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { IUniswapV3Pool } from "../../../../src/rebalancers/interfaces/IUniswapV3Pool.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPoolLiquidity" of contract "RebalancerUniswapV3".
 */
contract GetPoolLiquidity_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPoolLiquidity(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position
    ) public {
        // Given: A valid position.
        givenValidPosition(liquidityPool, initiatorParams, position);

        // When: Calling getPoolLiquidity.
        uint128 liquidity = rebalancer.getPoolLiquidity(position);

        // Then: It should return the correct values.
        assertEq(liquidity, IUniswapV3Pool(address(poolUniswap)).liquidity());
    }
}
