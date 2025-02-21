/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { UniswapV3CompounderSpot } from "./_UniswapV3CompounderSpot.fuzz.t.sol";
import { UniswapV3CompounderSpot_Fuzz_Test } from "./_UniswapV3CompounderSpot.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isBelowThreshold" of contract "UniswapV3CompounderSpot".
 */
contract IsBelowThreshold_UniswapV3CompounderSpot_Fuzz_Test is UniswapV3CompounderSpot_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3CompounderSpot_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_isBelowTreshold(
        UniswapV3CompounderSpot.PositionState memory position,
        UniswapV3CompounderSpot.Fees memory fees
    ) public {
        // When : Calling isBelowTreshold()
        bool isBelowThreshold = compounderSpot.isBelowThreshold(position, fees);

        // Then : It should always return "false".
        assertEq(isBelowThreshold, false);
    }
}
