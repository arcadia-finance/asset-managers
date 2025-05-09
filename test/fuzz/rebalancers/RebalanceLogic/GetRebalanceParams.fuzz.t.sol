/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { CLMath } from "../../../../src/libraries/CLMath.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalanceLogic_Fuzz_Test } from "./_RebalanceLogic.fuzz.t.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getRebalanceParams" of contract "RebalanceLogic".
 */
contract GetRebalanceParams_RebalanceLogic_Fuzz_Test is RebalanceLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    struct TestVariables {
        uint256 maxSlippageRatio;
        uint256 poolFee;
        uint256 initiatorFee;
        uint256 sqrtPrice;
        int24 tickLower;
        int24 tickUpper;
        uint64 balance0;
        uint64 balance1;
    }

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalanceLogic_Fuzz_Test) {
        RebalanceLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getRebalanceParams_BelowRange(TestVariables memory testVars) public {
        // Given: Reasonable current price.
        testVars.sqrtPrice = bound(testVars.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Reasonable balances.
        testVars.balance0 = uint64(bound(testVars.balance0, 1e6, type(uint64).max));
        testVars.balance1 = uint64(bound(testVars.balance1, 1e6, type(uint64).max));

        // And: Position is single sided in token0.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(testVars.sqrtPrice));
            testVars.tickLower = int24(bound(testVars.tickLower, tickCurrent + 1, TickMath.MAX_TICK - 1));
        }
        testVars.tickUpper = int24(bound(testVars.tickUpper, testVars.tickLower + 1, TickMath.MAX_TICK));
        uint160 sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        uint160 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        // And: Liquidity0 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance0 = testVars.balance0 + CLMath._getSpotValue(testVars.sqrtPrice, false, testVars.balance1);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount0(sqrtRatioLower, sqrtRatioUpper, maxBalance0) < type(uint128).max
            );
        }

        // And: Fee is smaller than MAX_FEE.
        testVars.initiatorFee = bound(testVars.initiatorFee, 0, MAX_FEE);
        testVars.poolFee = uint24(bound(testVars.poolFee, 0, (MAX_FEE - testVars.initiatorFee) / 1e12));

        // And: Slippage Ratio is smaller than MIN_LIQUIDITY_RATIO.
        testVars.maxSlippageRatio = bound(testVars.maxSlippageRatio, MIN_LIQUIDITY_RATIO, 1e18);

        // When: calling getRebalanceParams.
        RebalanceParams memory rebalanceParams = getRebalanceParams(sqrtRatioLower, sqrtRatioUpper, testVars);

        // Then: minLiquidity is non-zero and correct.
        assertGt(rebalanceParams.minLiquidity, 0);
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(testVars.sqrtPrice),
            uint160(sqrtRatioLower),
            uint160(sqrtRatioUpper),
            testVars.balance0 + rebalanceParams.amountOut,
            testVars.balance1 - rebalanceParams.amountIn - rebalanceParams.amountInitiatorFee
        );
        assertEq(rebalanceParams.minLiquidity, liquidity * testVars.maxSlippageRatio / 1e18);

        // And: zeroToOne is false.
        assertFalse(rebalanceParams.zeroToOne);

        // And: amountInitiatorFee is correct.
        assertEq(rebalanceParams.amountInitiatorFee, testVars.balance1 * testVars.initiatorFee / 1e18);

        // And: amountIn is correct.
        assertEq(rebalanceParams.amountIn, testVars.balance1 - rebalanceParams.amountInitiatorFee);

        // And: amountOut is correct.
        uint256 fee = testVars.initiatorFee + testVars.poolFee * 1e12;
        assertEq(rebalanceParams.amountOut, CLMath._getAmountOut(testVars.sqrtPrice, false, testVars.balance1, fee));
    }

    function testFuzz_Success_getRebalanceParams_AboveRange(TestVariables memory testVars) public {
        // Given: Reasonable current price.
        testVars.sqrtPrice = bound(testVars.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Reasonable balances.
        testVars.balance0 = uint64(bound(testVars.balance0, 1e6, type(uint64).max));
        testVars.balance1 = uint64(bound(testVars.balance1, 1e6, type(uint64).max));

        // And: Position is single sided in token0.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(testVars.sqrtPrice));
            testVars.tickUpper = int24(bound(testVars.tickUpper, TickMath.MIN_TICK + 1, tickCurrent));
        }
        testVars.tickLower = int24(bound(testVars.tickLower, TickMath.MIN_TICK, testVars.tickUpper - 1));
        uint160 sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        uint160 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        // And: Liquidity1 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance1 = testVars.balance1 + CLMath._getSpotValue(testVars.sqrtPrice, true, testVars.balance0);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, sqrtRatioUpper, maxBalance1) < type(uint128).max
            );
        }

        // And: Fee is smaller than MAX_FEE.
        testVars.initiatorFee = bound(testVars.initiatorFee, 0, MAX_FEE);
        testVars.poolFee = uint24(bound(testVars.poolFee, 0, (MAX_FEE - testVars.initiatorFee) / 1e12));

        // And: Slippage Ratio is smaller than MIN_LIQUIDITY_RATIO.
        testVars.maxSlippageRatio = bound(testVars.maxSlippageRatio, MIN_LIQUIDITY_RATIO, 1e18);

        // When: calling getRebalanceParams.
        RebalanceParams memory rebalanceParams = getRebalanceParams(sqrtRatioLower, sqrtRatioUpper, testVars);

        // Then: minLiquidity is non-zero and correct.
        assertGt(rebalanceParams.minLiquidity, 0);
        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            uint160(testVars.sqrtPrice),
            uint160(sqrtRatioLower),
            uint160(sqrtRatioUpper),
            testVars.balance0 - rebalanceParams.amountIn - rebalanceParams.amountInitiatorFee,
            testVars.balance1 + rebalanceParams.amountOut
        );
        assertEq(rebalanceParams.minLiquidity, liquidity * testVars.maxSlippageRatio / 1e18);

        // And: zeroToOne is true.
        assertTrue(rebalanceParams.zeroToOne);

        // And: amountInitiatorFee is correct.
        assertEq(rebalanceParams.amountInitiatorFee, testVars.balance0 * testVars.initiatorFee / 1e18);

        // And: amountIn is correct.
        assertEq(rebalanceParams.amountIn, testVars.balance0 - rebalanceParams.amountInitiatorFee);

        // And: amountOut is correct.
        uint256 fee = testVars.initiatorFee + testVars.poolFee * 1e12;
        assertEq(rebalanceParams.amountOut, CLMath._getAmountOut(testVars.sqrtPrice, true, testVars.balance0, fee));
    }

    function testFuzz_Success_getRebalanceParams_InRange_SmallerCurrentRatio(TestVariables memory testVars) public {
        // Given: Reasonable current price.
        testVars.sqrtPrice = bound(testVars.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Reasonable balances.
        testVars.balance0 = uint64(bound(testVars.balance0, 1e6, type(uint64).max));
        testVars.balance1 = uint64(bound(testVars.balance1, 1e6, type(uint64).max));

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(testVars.sqrtPrice));
            testVars.tickUpper = int24(bound(testVars.tickUpper, tickCurrent + 1, TickMath.MAX_TICK));
            testVars.tickLower = int24(bound(testVars.tickLower, TickMath.MIN_TICK, tickCurrent - 1));
        }
        uint160 sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        uint160 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        // And: Liquidity0 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance0 = testVars.balance0 + CLMath._getSpotValue(testVars.sqrtPrice, false, testVars.balance1);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount0(uint160(testVars.sqrtPrice), sqrtRatioUpper, maxBalance0)
                    < type(uint128).max
            );
        }

        // And: Liquidity1 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance1 = testVars.balance1 + CLMath._getSpotValue(testVars.sqrtPrice, true, testVars.balance0);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, uint160(testVars.sqrtPrice), maxBalance1)
                    < type(uint128).max
            );
        }

        // And: Fee is smaller than MAX_FEE.
        testVars.initiatorFee = bound(testVars.initiatorFee, 0, MAX_FEE);
        testVars.poolFee = uint24(bound(testVars.poolFee, 0, (MAX_FEE - testVars.initiatorFee) / 1e12));

        // And: Slippage Ratio is smaller than MIN_LIQUIDITY_RATIO.
        testVars.maxSlippageRatio = bound(testVars.maxSlippageRatio, MIN_LIQUIDITY_RATIO, 1e18);

        // And: Current ratio is lower than target ratio.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            uint256 token0ValueInToken1 = FullMath.mulDiv(testVars.balance0, testVars.sqrtPrice ** 2, CLMath.Q192);
            totalValueInToken1 = token0ValueInToken1 + testVars.balance1;
            currentRatio = uint256(testVars.balance1) * 1e18 / totalValueInToken1;
        }
        uint256 targetRatio = CLMath._getTargetRatio(testVars.sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
        vm.assume(currentRatio < targetRatio);

        // When: calling getSwapParams.
        RebalanceParams memory rebalanceParams = getRebalanceParams(sqrtRatioLower, sqrtRatioUpper, testVars);

        // Then: minLiquidity is non-zero and correct.
        assertGt(rebalanceParams.minLiquidity, 0);
        {
            uint256 liquidity;
            {
                uint256 balance0_ = testVars.balance0 - rebalanceParams.amountIn - rebalanceParams.amountInitiatorFee;
                uint256 balance1_ = testVars.balance1 + rebalanceParams.amountOut;
                liquidity = LiquidityAmounts.getLiquidityForAmounts(
                    uint160(testVars.sqrtPrice), sqrtRatioLower, sqrtRatioUpper, balance0_, balance1_
                );
            }
            assertEq(rebalanceParams.minLiquidity, liquidity * testVars.maxSlippageRatio / 1e18);
        }

        // Then: zeroToOne is true.
        assertTrue(rebalanceParams.zeroToOne);

        // And: amountOut is correct.
        uint256 fee = testVars.initiatorFee + testVars.poolFee * 1e12;
        {
            uint256 denominator = 1e18 + targetRatio * fee / (1e18 - fee);
            uint256 amountOutExpected = (targetRatio - currentRatio) * totalValueInToken1 / denominator;
            assertEq(rebalanceParams.amountOut, amountOutExpected);
        }

        // And: amountInitiatorFee is correct.
        uint256 amountInWithFee = CLMath._getAmountIn(testVars.sqrtPrice, true, rebalanceParams.amountOut, fee);
        uint256 amountInitiatorFee_ = amountInWithFee * testVars.initiatorFee / 1e18;
        assertEq(rebalanceParams.amountInitiatorFee, amountInitiatorFee_);

        // And: amountIn is correct.
        assertEq(rebalanceParams.amountIn, amountInWithFee - amountInitiatorFee_);
    }

    function testFuzz_Success_getRebalanceParams_InRange_BiggerCurrentRatio(TestVariables memory testVars) public {
        // Given: Reasonable current price.
        testVars.sqrtPrice = bound(testVars.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Reasonable balances.
        testVars.balance0 = uint64(bound(testVars.balance0, 1e6, type(uint64).max));
        testVars.balance1 = uint64(bound(testVars.balance1, 1e6, type(uint64).max));

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(testVars.sqrtPrice));
            testVars.tickUpper = int24(bound(testVars.tickUpper, tickCurrent + 1, TickMath.MAX_TICK));
            testVars.tickLower = int24(bound(testVars.tickLower, TickMath.MIN_TICK, tickCurrent - 1));
        }
        uint160 sqrtRatioLower = TickMath.getSqrtPriceAtTick(testVars.tickLower);
        uint160 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(testVars.tickUpper);

        // And: Liquidity0 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance0 = testVars.balance0 + CLMath._getSpotValue(testVars.sqrtPrice, false, testVars.balance1);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount0(uint160(testVars.sqrtPrice), sqrtRatioUpper, maxBalance0)
                    < type(uint128).max
            );
        }

        // And: Liquidity1 doesn't overflow (A lot of amount1 in very narrow ranges at small prices).
        {
            uint256 maxBalance1 = testVars.balance1 + CLMath._getSpotValue(testVars.sqrtPrice, true, testVars.balance0);
            vm.assume(
                LiquidityAmounts.getLiquidityForAmount1(sqrtRatioLower, uint160(testVars.sqrtPrice), maxBalance1)
                    < type(uint128).max
            );
        }

        // And: Fee is smaller than MAX_FEE.
        testVars.initiatorFee = bound(testVars.initiatorFee, 0, MAX_FEE);
        testVars.poolFee = uint24(bound(testVars.poolFee, 0, (MAX_FEE - testVars.initiatorFee) / 1e12));

        // And: Slippage Ratio is smaller than MIN_LIQUIDITY_RATIO.
        testVars.maxSlippageRatio = bound(testVars.maxSlippageRatio, MIN_LIQUIDITY_RATIO, 1e18);

        // And: Current ratio is lower than target ratio.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            uint256 token0ValueInToken1 = FullMath.mulDiv(testVars.balance0, testVars.sqrtPrice ** 2, CLMath.Q192);
            totalValueInToken1 = token0ValueInToken1 + testVars.balance1;
            currentRatio = uint256(testVars.balance1) * 1e18 / totalValueInToken1;
        }
        uint256 targetRatio = CLMath._getTargetRatio(testVars.sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
        vm.assume(currentRatio >= targetRatio);

        // When: calling getSwapParams.
        RebalanceParams memory rebalanceParams = getRebalanceParams(sqrtRatioLower, sqrtRatioUpper, testVars);

        // Then: minLiquidity is non-zero and correct.
        assertGt(rebalanceParams.minLiquidity, 0);
        {
            uint256 liquidity;
            {
                uint256 balance0_ = testVars.balance0 + rebalanceParams.amountOut;
                uint256 balance1_ = testVars.balance1 - rebalanceParams.amountIn - rebalanceParams.amountInitiatorFee;
                liquidity = LiquidityAmounts.getLiquidityForAmounts(
                    uint160(testVars.sqrtPrice), sqrtRatioLower, sqrtRatioUpper, balance0_, balance1_
                );
            }
            assertEq(rebalanceParams.minLiquidity, liquidity * testVars.maxSlippageRatio / 1e18);
        }

        // And: zeroToOne is false.
        assertFalse(rebalanceParams.zeroToOne);

        // And: amountInitiatorFee is correct.
        uint256 fee = testVars.initiatorFee + testVars.poolFee * 1e12;
        uint256 amountInWithFee;
        {
            uint256 denominator = 1e18 - targetRatio * fee / 1e18;
            amountInWithFee = (currentRatio - targetRatio) * totalValueInToken1 / denominator;
            uint256 amountInitiatorFee_ = amountInWithFee * testVars.initiatorFee / 1e18;
            assertEq(rebalanceParams.amountInitiatorFee, amountInitiatorFee_);
        }

        // And: amountIn is correct.
        assertEq(rebalanceParams.amountIn, amountInWithFee - rebalanceParams.amountInitiatorFee);

        // And: amountOut is correct.
        assertEq(rebalanceParams.amountOut, CLMath._getAmountOut(testVars.sqrtPrice, false, amountInWithFee, fee));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
    function getRebalanceParams(uint256 sqrtRatioLower, uint256 sqrtRatioUpper, TestVariables memory testVars)
        internal
        view
        returns (RebalanceParams memory rebalanceParams)
    {
        return rebalanceLogic.getRebalanceParams(
            testVars.maxSlippageRatio,
            testVars.poolFee,
            testVars.initiatorFee,
            testVars.sqrtPrice,
            sqrtRatioLower,
            sqrtRatioUpper,
            testVars.balance0,
            testVars.balance1
        );
    }
}
