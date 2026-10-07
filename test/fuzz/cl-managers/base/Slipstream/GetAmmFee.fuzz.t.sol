/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Slipstream_Fuzz_Test } from "./_Slipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getAmmFee" of contract "Slipstream".
 */
contract GetAmmFee_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Slipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmmFee(uint128 liquidityPool, PositionState memory position, uint24 ammFee) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);
        PositionState memory position_ = base.getPositionState(address(slipstreamPositionManager), position.id);

        // And: The swap fee module returns another fee since the position state was read.
        ammFee = uint24(bound(ammFee, 0, MAX_POOL_FEE));
        swapFeeModule.setFee(address(poolCl), ammFee);

        // When: Calling getAmmFee.
        uint24 ammFee_ = base.getAmmFee(position_);

        // Then: It returns the fee the AMM charges at the time of the call.
        assertEq(ammFee_, ammFee);
    }
}
