/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamCompounder } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isBelowThreshold" of contract "SlipstreamCompounder".
 */
contract IsBelowThreshold_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isBelowTreshold_true(SlipstreamCompounder.PositionState memory position) public {
        // Given : Total value of fees is below COMPOUND_TRESHOLD 9.99$ < 10$
        position.usdPriceToken0 = 1e30;
        position.usdPriceToken1 = 1e18;

        SlipstreamCompounder.Fees memory fees;
        fees.amount0 = 4.99 * 1e6;
        fees.amount1 = 5 * 1e18;

        // When : Calling isBelowTreshold()
        bool isBelowThreshold = compounder.isBelowThreshold(position, fees);

        // Then : It should return "true"
        assertEq(isBelowThreshold, true);
    }

    function testFuzz_Success_isBelowTreshold_false(SlipstreamCompounder.PositionState memory position) public {
        // Given : Total value of fees is  above COMPOUND_TRESHOLD 10,01$ > 10$
        position.usdPriceToken0 = 1e30;
        position.usdPriceToken1 = 1e18;

        SlipstreamCompounder.Fees memory fees;
        fees.amount0 = 5.01 * 1e6;
        fees.amount1 = 5 * 1e18;

        // When : Calling isBelowTreshold()
        bool isBelowThreshold = compounder.isBelowThreshold(position, fees);

        // Then : It should return "true"
        assertEq(isBelowThreshold, false);
    }
}
