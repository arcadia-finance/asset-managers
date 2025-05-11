/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "RebalancerUniswapV3".
 */
contract GetPositionState_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState(uint128 liquidityPool, Rebalancer.PositionState memory position)
        public
    {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPositionState.
        Rebalancer.PositionState memory position_ =
            rebalancer.getPositionState(address(nonfungiblePositionManager), position.id);

        // Then: It should return the correct position.
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.id, position.id);
        assertEq(position_.fee, POOL_FEE);
        assertEq(position_.tickSpacing, poolUniswap.tickSpacing());
        assertEq(position_.tickCurrent, TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice)));
        assertEq(position_.tickLower, position.tickLower);
        assertEq(position_.tickUpper, position.tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtPrice, position.sqrtPrice);
        assertEq(position_.tokens.length, 2);
        assertEq(position_.tokens[0], address(token0));
        assertEq(position_.tokens[1], address(token1));
    }
}
