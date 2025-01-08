/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamCompounderSpot } from "./_SlipstreamCompounderSpot.fuzz.t.sol";
import { SlipstreamCompounderSpot_Fuzz_Test } from "./_SlipstreamCompounderSpot.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isBelowThreshold" of contract "SlipstreamCompounderSpot".
 */
contract IsBelowThreshold_SlipstreamCompounderSpot_Fuzz_Test is SlipstreamCompounderSpot_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounderSpot_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isBelowTreshold(
        SlipstreamCompounderSpot.PositionState memory position,
        SlipstreamCompounderSpot.Fees memory fees
    ) public {
        // When : Calling isBelowTreshold()
        bool isBelowThreshold = compounderSpot.isBelowThreshold(position, fees);

        // Then : It should always return "false".
        assertEq(isBelowThreshold, false);
    }
}
