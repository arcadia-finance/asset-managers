/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getUnderlyingTokens" of contract "UniswapV3".
 */
contract GetUnderlyingTokens_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getUnderlyingTokens(uint128 liquidityPool, PositionState memory position) public {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        (address token0_, address token1_) = base.getUnderlyingTokens(address(nonfungiblePositionManager), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(token0));
        assertEq(token1_, address(token1));
    }
}
