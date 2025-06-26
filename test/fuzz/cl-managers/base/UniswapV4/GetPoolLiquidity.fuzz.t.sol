/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPoolLiquidity" of contract "UniswapV4".
 */
contract GetPoolLiquidity_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
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
        uint128 liquidity = base.getPoolLiquidity(position);

        // Then: It should return the correct values.
        assertEq(liquidity, stateView.getLiquidity(poolKey.toId()));
    }
}
