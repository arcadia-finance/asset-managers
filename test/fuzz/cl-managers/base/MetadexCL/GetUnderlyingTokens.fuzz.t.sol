/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "_getUnderlyingTokens" of contract "Slipstream", on Metadex CL.
 */
contract GetUnderlyingTokens_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getUnderlyingTokens_MetadexCL(uint128 liquidityPool, PositionState memory position)
        public
    {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // When: Calling getUnderlyingTokens.
        (address token0_, address token1_) = base.getUnderlyingTokens(address(metadex03PositionManager), position.id);

        // Then: It should return the correct values.
        assertEq(token0_, address(token0));
        assertEq(token1_, address(token1));
    }
}
