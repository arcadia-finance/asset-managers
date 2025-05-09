/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";
import { UniswapV4Logic } from "../../../../src/compounders/uniswap-v4/libraries/UniswapV4Logic.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParameters" of contract "UniswapV4Compounder".
 */
contract GetSwapParameters_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSwapParameters_currentTickGreaterOrEqualToTickUpper(
        TestVariables memory testVars,
        FeeGrowth memory feeData
    ) public {
        // Given : Valid State.
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted.
        setState(testVars, stablePoolKey);

        // And : Set valid fee state.
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        // And : newTick = tickUpper.
        int24 newTick = testVars.tickUpper;
        uint160 newSqrtPrice = TickMath.getSqrtPriceAtTick(newTick);

        UniswapV4Compounder.PositionState memory position;
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);
        position.sqrtPrice = newSqrtPrice;

        UniswapV4Compounder.Fees memory fees;
        fees.amount0 = feeData.desiredFee0;
        fees.amount1 = feeData.desiredFee1;

        // When : calling getSwapParameters().
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid.
        assertEq(zeroToOne, true);

        uint256 amountOutExpected = UniswapV4Logic._getAmountOut(position.sqrtPrice, true, fees.amount0);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getSwapParameters_currentTickSmallerThanTickLower(
        TestVariables memory testVars,
        FeeGrowth memory feeData
    ) public {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        setState(testVars, stablePoolKey);

        // And : Set valid fee state.
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        // And : newTick < tickLower.
        int24 newTick = testVars.tickLower - 1;
        uint160 newSqrtPrice = TickMath.getSqrtPriceAtTick(newTick);

        UniswapV4Compounder.PositionState memory position;
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);
        position.sqrtPrice = newSqrtPrice;

        UniswapV4Compounder.Fees memory fees;
        fees.amount0 = feeData.desiredFee0;
        fees.amount1 = feeData.desiredFee1;

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, false);

        uint256 amountOutExpected = UniswapV4Logic._getAmountOut(position.sqrtPrice, false, fees.amount1);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getSwapParameters_tickInRangeWithExcessToken0Fees(
        TestVariables memory testVars,
        FeeGrowth memory feeData
    ) public {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);
        // And : State is persisted
        setState(testVars, stablePoolKey);

        // And : totalFee0 is greater than totalFee1
        // And : currentTick unchanged (50/50)
        // Case for currentRatio < targetRatio
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max - 2);
        feeData.desiredFee0 = bound(feeData.desiredFee0, feeData.desiredFee1 + 1, type(uint16).max);
        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        (uint160 sqrtPrice,,,) = stateView.getSlot0(stablePoolKey.toId());

        UniswapV4Compounder.PositionState memory position;
        position.sqrtPrice = sqrtPrice;
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        UniswapV4Compounder.Fees memory fees;
        fees.amount0 = feeData.desiredFee0;
        fees.amount1 = feeData.desiredFee1;

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, true);

        uint256 expectedAmountOut;
        {
            // Calculate targetRatio
            uint256 sqrtPriceLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
            uint256 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);
            uint256 numerator = position.sqrtPrice - sqrtPriceLower;
            uint256 denominator = 2 * position.sqrtPrice - sqrtPriceLower - position.sqrtPrice ** 2 / sqrtPriceUpper;
            uint256 targetRatio = numerator.mulDivDown(1e18, denominator);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV4Logic._getAmountOut(position.sqrtPrice, true, fees.amount0);
            uint256 totalFeeValueInToken1 = fees.amount1 + fee0ValueInToken1;
            uint256 currentRatio = fees.amount1.mulDivDown(1e18, totalFeeValueInToken1);

            expectedAmountOut = (targetRatio - currentRatio).mulDivDown(totalFeeValueInToken1, 1e18);
        }

        assertEq(amountOut, expectedAmountOut);
        // And : Further testing will validate the swap results based on above ratios in compoundFees testing.
    }

    function testFuzz_Success_getSwapParameters_tickInRangeWithExcessToken1Fees(
        TestVariables memory testVars,
        FeeGrowth memory feeData
    ) public {
        // Given : Valid State
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        setState(testVars, stablePoolKey);

        // And : totalFee1 is greater than totalFee0
        // And : currentTick unchanged (50/50)
        // Case for currentRatio >= targetRatio
        feeData.desiredFee0 = 0;
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1000, type(uint16).max);

        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        (uint160 sqrtPrice,,,) = stateView.getSlot0(stablePoolKey.toId());
        UniswapV4Compounder.PositionState memory position;
        position.sqrtPrice = sqrtPrice;
        position.sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        UniswapV4Compounder.Fees memory fees;
        fees.amount0 = feeData.desiredFee0;
        fees.amount1 = feeData.desiredFee1;

        // When : calling getSwapParameters()
        (bool zeroToOne, uint256 amountOut) = compounder.getSwapParameters(position, fees);

        // Then : Returned values should be valid
        assertEq(zeroToOne, false);

        uint256 expectedAmountOut;
        {
            // Calculate targetRatio
            uint256 sqrtPriceLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
            uint256 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);
            uint256 numerator = position.sqrtPrice - sqrtPriceLower;
            uint256 denominator = 2 * position.sqrtPrice - sqrtPriceLower - position.sqrtPrice ** 2 / sqrtPriceUpper;
            uint256 targetRatio = numerator.mulDivDown(1e18, denominator);

            // Calculate the total fee value in token1 equivalent:
            uint256 fee0ValueInToken1 = UniswapV4Logic._getAmountOut(position.sqrtPrice, true, fees.amount0);
            uint256 totalFeeValueInToken1 = fees.amount1 + fee0ValueInToken1;
            uint256 currentRatio = fees.amount1.mulDivDown(1e18, totalFeeValueInToken1);

            uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalFeeValueInToken1, 1e18);
            expectedAmountOut = UniswapV4Logic._getAmountOut(position.sqrtPrice, false, amountIn);
        }

        assertEq(amountOut, expectedAmountOut);
        // And : Further testing will validate the swap results based on above ratios in compoundFees testing.
    }
}
