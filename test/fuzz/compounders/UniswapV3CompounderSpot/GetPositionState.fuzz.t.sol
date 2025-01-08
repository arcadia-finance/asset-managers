/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { TwapLogic } from "../../../../src/libraries/TwapLogic.sol";
import { UniswapV3CompounderSpot } from "../../../../src/compounders/uniswap-v3/UniswapV3CompounderSpot.sol";
import { UniswapV3CompounderSpot_Fuzz_Test } from "./_UniswapV3CompounderSpot.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "UniswapV3CompounderSpot".
 */
contract GetPositionState_UniswapV3CompounderSpot_Fuzz_Test is UniswapV3CompounderSpot_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3CompounderSpot_Fuzz_Test.setUp();
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

        // And: The minimum time interval to calculate TWAT should have passed.
        vm.warp(block.timestamp + TwapLogic.TWAT_INTERVAL);

        // When : Calling getPositionState()
        UniswapV3CompounderSpot.PositionState memory position = compounderSpot.getPositionState(tokenId);

        // Then : It should return the correct values
        assertEq(position.token0, address(token0));
        assertEq(position.token1, address(token1));
        assertEq(position.fee, POOL_FEE);
        assertEq(position.sqrtRatioLower, TickMath.getSqrtRatioAtTick(testVars.tickLower));
        assertEq(position.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(testVars.tickUpper));

        (uint160 sqrtPriceX96,,,,,,) = usdStablePool.slot0();
        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        // Get twat values
        int24 twat = TwapLogic._getTwat(position.pool);
        uint256 twaSqrtRatioX96 = TickMath.getSqrtRatioAtTick(twat);

        uint256 lowerBoundSqrtPriceX96 = twaSqrtRatioX96.mulDivDown(compounderSpot.LOWER_SQRT_PRICE_DEVIATION(), 1e18);
        uint256 upperBoundSqrtPriceX96 = twaSqrtRatioX96.mulDivDown(compounderSpot.UPPER_SQRT_PRICE_DEVIATION(), 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96);
    }
}
