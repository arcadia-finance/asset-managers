/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ICLPool } from "../../../../src/interfaces/ICLPool.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Slipstream_Fuzz_Test } from "./_Slipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPoolLiquidity" of contract "Slipstream".
 */
contract GetPoolLiquidity_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Slipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPoolLiquidity(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getPoolLiquidity.
        uint128 liquidity = base.getPoolLiquidity(position);

        // Then: It should return the correct values.
        assertEq(liquidity, ICLPool(address(poolCl)).liquidity());
    }
}
