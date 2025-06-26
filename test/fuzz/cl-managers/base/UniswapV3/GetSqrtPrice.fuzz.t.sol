/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPrice" of contract "UniswapV3".
 */
contract GetSqrtPrice_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPrice(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getSqrtPrice.
        uint160 sqrtPrice = base.getSqrtPrice(position);

        // Then: It should return the correct values.
        (uint160 sqrtPrice_,,,,,,) = poolUniswap.slot0();
        assertEq(sqrtPrice, sqrtPrice_);
    }
}
