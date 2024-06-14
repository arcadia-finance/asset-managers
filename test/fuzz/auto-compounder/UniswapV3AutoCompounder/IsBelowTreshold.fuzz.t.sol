/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3AutoCompounder } from "./_UniswapV3AutoCompounder.fuzz.t.sol";
import { UniswapV3AutoCompounder_Fuzz_Test } from "./_UniswapV3AutoCompounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_isBelowThreshold" of contract "UniswapV3AutoCompounder".
 */
contract IsBelowThreshold_UniswapV3AutoCompounder_Fuzz_Test is UniswapV3AutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3AutoCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_success_isBelowTreshold_true(UniswapV3AutoCompounder.PositionState memory position) public {
        // Given : Total value of fees is below COMPOUND_TRESHOLD 9.99$ < 10$
        position.usdPriceToken0 = 1e30;
        position.usdPriceToken1 = 1e18;

        UniswapV3AutoCompounder.Fees memory fees;
        fees.amount0 = 4.99 * 1e6;
        fees.amount1 = 5 * 1e18;

        // When : Calling isBelowTreshold()
        bool isBelowThreshold = autoCompounder.isBelowThreshold(position, fees);

        // Then : It should return "true"
        assertEq(isBelowThreshold, true);
    }

    function testFuzz_success_isBelowTreshold_false(UniswapV3AutoCompounder.PositionState memory position) public {
        // Given : Total value of fees is  above COMPOUND_TRESHOLD 10,01$ > 10$
        position.usdPriceToken0 = 1e30;
        position.usdPriceToken1 = 1e18;

        UniswapV3AutoCompounder.Fees memory fees;
        fees.amount0 = 5.01 * 1e6;
        fees.amount1 = 5 * 1e18;

        // When : Calling isBelowTreshold()
        bool isBelowThreshold = autoCompounder.isBelowThreshold(position, fees);

        // Then : It should return "true"
        assertEq(isBelowThreshold, false);
    }
}
