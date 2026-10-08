/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getAmmFee" of contract "UniswapV3".
 */
contract GetAmmFee_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmmFee(uint128 liquidityPool, PositionState memory position) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);
        PositionState memory position_ = base.getPositionState(address(nonfungiblePositionManager), position.id);

        // When: Calling getAmmFee.
        uint24 ammFee = base.getAmmFee(position_);

        // Then: It returns the fee tier of the pool.
        assertEq(ammFee, position.poolFee);
    }
}
