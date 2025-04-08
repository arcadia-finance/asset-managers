/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamLogic } from "../../../../src/compounders/slipstream/libraries/SlipstreamLogic.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "SlipstreamCompounder".
 */
contract GetPositionState_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState(TestVariables memory testVars) public {
        // Given : Valid State
        bool token0HasLowestDecimals;
        (testVars, token0HasLowestDecimals) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);
        (uint160 sqrtPriceX96,,,,,) = usdStablePool.slot0();

        // When : Calling getPositionState()
        SlipstreamCompounder.PositionState memory position =
            compounder.getPositionState(tokenId, sqrtPriceX96, initiator);

        // Then : It should return the correct values
        assertEq(position.token0, address(token0));
        assertEq(position.token1, address(token1));
        assertEq(position.tickSpacing, TICK_SPACING);
        assertEq(position.sqrtRatioLower, TickMath.getSqrtRatioAtTick(testVars.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(testVars.tickUpper));

        assertEq(position.pool, address(usdStablePool));
        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        (uint64 upperSqrtPriceDeviation, uint64 lowerSqrtPriceDeviation,) = compounder.initiatorInfo(initiator);
        uint256 lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(uint256(lowerSqrtPriceDeviation), 1e18);
        uint256 upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(uint256(upperSqrtPriceDeviation), 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96);
    }
}
