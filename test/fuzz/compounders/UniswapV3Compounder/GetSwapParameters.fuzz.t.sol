/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Compounder } from "./_UniswapV3Compounder.fuzz.t.sol";
import { UniswapV3Compounder_Fuzz_Test } from "./_UniswapV3Compounder.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/compounders/uniswap-v3/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParameters" of contract "UniswapV3Compounder".
 */
contract GetSwapParameters_UniswapV3Compounder_Fuzz_Test is UniswapV3Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSwapParameters_currentTickGreaterOrEqualToTickUpper(TestVariables memory testVars)
        public
    {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        setState(testVars, usdStablePool);

        // And : newTick = tickUpper
        int24 newTick = testVars.tickUpper;
        usdStablePool.setCurrentTick(newTick);

        uint160 sqrtPriceX96AtCurrentTick = TickMath.getSqrtRatioAtTick(newTick);

        UniswapV3Compounder.PositionState memory position;
        position.currentTick = newTick;
        position.tickLower = testVars.tickLower;
        position.tickUpper = testVars.tickUpper;
        position.sqrtPriceX96 = sqrtPriceX96AtCurrentTick;

        UniswapV3Compounder.Fees memory fees;
        fees.amount0 = testVars.feeAmount0 * 10 ** token0.decimals();
        fees.amount1 = testVars.feeAmount1 * 10 ** token1.decimals();

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, true);

        uint256 amountOutExpected = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getSwapParameters_currentTickSmallerOrEqualToTickLower(TestVariables memory testVars)
        public
    {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        setState(testVars, usdStablePool);

        // And : newTick = tickLower
        int24 newTick = testVars.tickLower;
        usdStablePool.setCurrentTick(newTick);

        uint160 sqrtPriceX96AtCurrentTick = TickMath.getSqrtRatioAtTick(newTick);

        UniswapV3Compounder.PositionState memory position;
        position.currentTick = newTick;
        position.tickLower = testVars.tickLower;
        position.tickUpper = testVars.tickUpper;
        position.sqrtPriceX96 = sqrtPriceX96AtCurrentTick;

        UniswapV3Compounder.Fees memory fees;
        fees.amount0 = testVars.feeAmount0 * 10 ** token0.decimals();
        fees.amount1 = testVars.feeAmount1 * 10 ** token1.decimals();

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, false);

        uint256 amountOutExpected = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, fees.amount1);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getSwapParameters_tickInRangeWithExcessToken0Fees(TestVariables memory testVars) public {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars);

        // And : totalFee0 is greater than totalFee1
        // And : currentTick unchanged (50/50)
        // Case for currentRatio < targetRatio
        testVars.feeAmount0 = bound(testVars.feeAmount0, testVars.feeAmount1 + 1, uint256(type(uint16).max) + 1);

        // And : State is persisted
        setState(testVars, usdStablePool);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = usdStablePool.slot0();
        UniswapV3Compounder.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.currentTick = currentTick;
        position.tickLower = testVars.tickLower;
        position.tickUpper = testVars.tickUpper;

        UniswapV3Compounder.Fees memory fees;
        fees.amount0 = testVars.feeAmount0 * 10 ** token0.decimals();
        fees.amount1 = testVars.feeAmount1 * 10 ** token1.decimals();

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, true);

        uint256 expectedAmountOut;
        {
            // Calculate targetRatio
            uint256 ticksCurrentToUpper = uint256(position.tickUpper - position.currentTick);
            uint256 ticksLowerToUpper = uint256(position.tickUpper - position.tickLower);
            uint256 targetRatio = ticksCurrentToUpper.mulDivDown(1e18, ticksLowerToUpper);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
            uint256 totalFeeValueInToken1 = fees.amount1 + fee0ValueInToken1;
            uint256 currentRatio = fees.amount1.mulDivDown(1e18, totalFeeValueInToken1);

            expectedAmountOut = (targetRatio - currentRatio).mulDivDown(totalFeeValueInToken1, 1e18);
        }

        assertEq(amountOut, expectedAmountOut);
        // And : Further testing will validate the swap results based on above ratios in compoundFees testing.
    }

    function testFuzz_Success_getSwapParameters_tickInRangeWithExcessToken1Fees(TestVariables memory testVars) public {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars);

        // And : totalFee1 is greater than totalFee0
        // And : currentTick unchanged (50/50)
        // Case for currentRatio >= targetRatio
        testVars.feeAmount1 = bound(testVars.feeAmount1, testVars.feeAmount0 + 1, uint256(type(uint16).max) + 1);

        // And : State is persisted
        setState(testVars, usdStablePool);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = usdStablePool.slot0();
        UniswapV3Compounder.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.currentTick = currentTick;
        position.tickLower = testVars.tickLower;
        position.tickUpper = testVars.tickUpper;

        UniswapV3Compounder.Fees memory fees;
        fees.amount0 = testVars.feeAmount0 * 10 ** token0.decimals();
        fees.amount1 = testVars.feeAmount1 * 10 ** token1.decimals();

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, false);

        uint256 expectedAmountOut;
        {
            // Calculate targetRatio
            uint256 ticksCurrentToUpper = uint256(position.tickUpper - position.currentTick);
            uint256 ticksLowerToUpper = uint256(position.tickUpper - position.tickLower);
            uint256 targetRatio = ticksCurrentToUpper.mulDivDown(1e18, ticksLowerToUpper);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, fees.amount0);
            uint256 totalFeeValueInToken1 = fees.amount1 + fee0ValueInToken1;
            uint256 currentRatio = fees.amount1.mulDivDown(1e18, totalFeeValueInToken1);

            uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalFeeValueInToken1, 1e18);
            expectedAmountOut = amountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amountIn);
        }

        assertEq(amountOut, expectedAmountOut);
        // And : Further testing will validate the swap results based on above ratios in compoundFees testing.
    }
}
