/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../src/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getUnderlyingTokens" of contract "UniswapV4".
 */
contract GetUnderlyingTokens_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
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
        (address token0_, address token1_) = base.getUnderlyingTokens(address(positionManagerV4), position.id);

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
        (address token0_, address token1_) = base.getUnderlyingTokens(address(positionManagerV4), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(weth9));
        assertEq(token1_, address(token1));
    }
}
