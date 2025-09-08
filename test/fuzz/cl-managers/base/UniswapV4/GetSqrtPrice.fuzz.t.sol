/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSqrtPrice" of contract "UniswapV4".
 */
contract GetSqrtPrice_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSqrtPrice(uint128 liquidityPool, PositionState memory position, bool native) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, native);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getSqrtPrice.
        uint160 sqrtPrice = base.getSqrtPrice(position);

        // Then: It should return the correct values.
        (uint160 sqrtPrice_,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPrice, sqrtPrice_);
    }
}
