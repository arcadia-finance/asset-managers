/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceLogic } from "../../../../src/rebalancers/libraries/RebalanceLogic.sol";
import { RebalanceLogic_Fuzz_Test } from "./_RebalanceLogic.fuzz.t.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParams" of contract "RebalanceLogic".
 */
contract GetSwapParams_RebalanceLogic_Fuzz_Test is RebalanceLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_FEE = 0.01 * 1e18;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalanceLogic_Fuzz_Test) {
        RebalanceLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getSwapParams_BelowRange(
        uint256 sqrtPrice,
        int24 tickLower,
        int24 tickUpper,
        uint128 balance0,
        uint128 balance1,
        uint256 fee
    ) public {
        // Given: sqrtPrice is smaller than type(uint128).max (no overflow).
        sqrtPrice = bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, type(uint128).max);

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
        tickLower = int24(bound(tickLower, tickCurrent + 1, TickMath.MAX_TICK - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, TickMath.MAX_TICK));
        uint256 sqrtRatioLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // And: fee is smaller than MAX_FEE (invariant).
        fee = bound(fee, 0, MAX_FEE);

        // When: calling getSwapParams.
        (bool zeroToOne, uint256 amountIn, uint256 amountOut) =
            rebalanceLogic.getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Then: zeroToOne is false.
        assertFalse(zeroToOne);

        // And: amountIn is equal to balance1.
        assertEq(amountIn, balance1);

        // And: amountOut is correct.
        assertEq(amountOut, rebalanceLogic.getAmountOut(sqrtPrice, false, balance1, fee));
    }

    function testFuzz_Success_getSwapParams_AboveRange(
        uint256 sqrtPrice,
        int24 tickLower,
        int24 tickUpper,
        uint128 balance0,
        uint128 balance1,
        uint256 fee
    ) public {
        // Given: sqrtPrice is smaller than type(uint128).max (no overflow).
        sqrtPrice = bound(sqrtPrice, TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 2), type(uint128).max);

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
        tickUpper = int24(bound(tickUpper, TickMath.MIN_TICK + 1, tickCurrent));
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tickUpper - 1));
        uint256 sqrtRatioLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // And: fee is smaller than MAX_FEE (invariant).
        fee = bound(fee, 0, MAX_FEE);

        // When: calling getSwapParams.
        (bool zeroToOne, uint256 amountIn, uint256 amountOut) =
            rebalanceLogic.getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Then: zeroToOne is false.
        assertTrue(zeroToOne);

        // And: amountIn is equal to balance0.
        assertEq(amountIn, balance0);

        // And: amountOut is correct.
        assertEq(amountOut, rebalanceLogic.getAmountOut(sqrtPrice, true, balance0, fee));
    }

    function testFuzz_Success_getSwapParams_InRange_SmallerCurrentRatio(
        int24 tickLower,
        int24 tickUpper,
        uint256 sqrtPrice,
        uint128 balance0,
        uint128 balance1,
        uint256 fee
    ) public {
        // Given: sqrtPrice is smaller than type(uint128).max (no overflow).
        {
            uint256 sqrtPriceMin = TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1);
            sqrtPrice = bound(sqrtPrice, sqrtPriceMin, type(uint128).max);
        }

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
            tickUpper = int24(bound(tickUpper, tickCurrent + 1, TickMath.MAX_TICK));
            tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tickCurrent - 1));
        }

        uint256 sqrtRatioLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // And: fee is smaller than MAX_FEE (invariant).
        fee = bound(fee, 0, MAX_FEE);

        // And: No overflow due to enormous amounts.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (sqrtPrice ** 2 > RebalanceLogic.Q192) {
                balance0 =
                    uint128(bound(balance0, 0, FullMath.mulDiv(type(uint256).max, RebalanceLogic.Q192, sqrtPrice ** 2)));
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(balance0, sqrtPrice ** 2, RebalanceLogic.Q192);
            balance1 = uint128(bound(balance1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + balance1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(balance1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = rebalanceLogic.getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
        vm.assume(currentRatio < targetRatio);

        // When: calling getSwapParams.
        (bool zeroToOne, uint256 amountIn, uint256 amountOut) =
            rebalanceLogic.getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Then: zeroToOne is true.
        assertTrue(zeroToOne);

        // And: amountOut is correct.
        {
            uint256 denominator = 1e18 + targetRatio * fee / (1e18 - fee);
            uint256 amountOutExpected = (targetRatio - currentRatio) * totalValueInToken1 / denominator;
            assertEq(amountOut, amountOutExpected);
        }

        // And: amountIn is correct.
        assertEq(amountIn, rebalanceLogic.getAmountIn(sqrtPrice, true, amountOut, fee));
    }

    function testFuzz_Success_getSwapParams_InRange_BiggerCurrentRatio(
        int24 tickLower,
        int24 tickUpper,
        uint256 sqrtPrice,
        uint128 balance0,
        uint128 balance1,
        uint256 fee
    ) public {
        // Given: sqrtPrice is smaller than type(uint128).max (no overflow).
        {
            uint256 sqrtPriceMin = TickMath.getSqrtPriceAtTick(TickMath.MIN_TICK + 1);
            sqrtPrice = bound(sqrtPrice, sqrtPriceMin, type(uint128).max);
        }

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
            tickUpper = int24(bound(tickUpper, tickCurrent + 1, TickMath.MAX_TICK));
            tickLower = int24(bound(tickLower, TickMath.MIN_TICK, tickCurrent - 1));
        }

        uint256 sqrtRatioLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(tickUpper);

        // And: fee is smaller than MAX_FEE (invariant).
        fee = bound(fee, 0, MAX_FEE);

        // And: No overflow due to enormous amounts.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (sqrtPrice ** 2 > RebalanceLogic.Q192) {
                balance0 =
                    uint128(bound(balance0, 0, FullMath.mulDiv(type(uint256).max, RebalanceLogic.Q192, sqrtPrice ** 2)));
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(balance0, sqrtPrice ** 2, RebalanceLogic.Q192);
            balance1 = uint128(bound(balance1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + balance1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(balance1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = rebalanceLogic.getTargetRatio(sqrtPrice, sqrtRatioLower, sqrtRatioUpper);
        vm.assume(currentRatio >= targetRatio);

        // When: calling getSwapParams.
        (bool zeroToOne, uint256 amountIn, uint256 amountOut) =
            rebalanceLogic.getSwapParams(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1, fee);

        // Then: zeroToOne is true.
        assertFalse(zeroToOne);

        // And: amountIn is correct.
        {
            uint256 denominator = 1e18 - targetRatio * fee / 1e18;
            uint256 amountInExpected = (currentRatio - targetRatio) * totalValueInToken1 / denominator;
            assertEq(amountIn, amountInExpected);
        }

        // And: amountOut is correct.
        assertEq(amountOut, rebalanceLogic.getAmountOut(sqrtPrice, false, amountIn, fee));
    }
}
