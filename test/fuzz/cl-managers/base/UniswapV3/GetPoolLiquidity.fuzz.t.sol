/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IUniswapV3Pool } from "../../../../../src/cl-managers/interfaces/IUniswapV3Pool.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPoolLiquidity" of contract "UniswapV3".
 */
contract GetPoolLiquidity_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPoolLiquidity(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPoolLiquidity.
        uint128 liquidity = base.getPoolLiquidity(position);

        // Then: It should return the correct values.
        assertEq(liquidity, IUniswapV3Pool(address(poolUniswap)).liquidity());
    }
}
