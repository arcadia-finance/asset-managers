/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../src/state/PositionState.sol";
import { UniswapV4 } from "../../../../src/base/UniswapV4.sol";
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
    function testFuzz_revert_getUnderlyingTokens_InvalidPool(uint128 liquidityPool, PositionState memory position)
        public
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);

        deployNativeAM();
        poolKey = initializePoolV4(
            address(0), address(weth9), uint160(position.sqrtPrice), address(0), position.fee, position.tickSpacing
        );
        position.tokens = new address[](2);
        position.tokens[0] = address(0);
        position.tokens[1] = address(weth9);

        int24 tickSpacing = position.tickSpacing;
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e12));
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        // Then: It should revert.
        vm.expectRevert(UniswapV4.InvalidPool.selector);
        base.getUnderlyingTokens(address(positionManagerV4), position.id);
    }

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
