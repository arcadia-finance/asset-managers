/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/LiquidityAmounts.sol";
import { NoSlippageSwapMath } from "../../../../src/rebalancers/uniswap-v3/libraries/NoSlippageSwapMath.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/uniswap-v3/libraries/UniswapV3Logic.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParams" of contract "UniswapV3Rebalancer".
 */
contract GetSwapParams_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getSwapParams_SingleSidedToken0_OverflowSqrtPriceX96(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        position.sqrtPriceX96 =
            bound(position.sqrtPriceX96, uint256(type(uint128).max) + 1, TickMath.MAX_SQRT_RATIO - 1);

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.newLowerTick = int24(bound(position.newLowerTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: Ticks don't overflow (invariant Uniswap).
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getSwapParams().
        // Then: Function overflows.
        vm.expectRevert(stdError.arithmeticError);
        rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);
    }

    function testFuzz_Success_getSwapParams_SingleSidedToken0(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_RATIO, type(uint128).max);

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.newLowerTick = int24(bound(position.newLowerTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: Ticks don't overflow (invariant Uniswap).
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getSwapParams().
        (bool zeroToOne, uint256 amountIn, uint256 amountOut,) =
            rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is false.
        assertFalse(zeroToOne);

        // And: amountIn is equal to amount1.
        assertEq(amountIn, amount1);

        // And: amountOut is correct.
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountOutExpected = NoSlippageSwapMath._getAmountOut(position.sqrtPriceX96, false, amount1, fee);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Revert_getSwapParams_SingleSidedToken1_OverflowSqrtPriceX96(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        position.sqrtPriceX96 =
            bound(position.sqrtPriceX96, uint256(type(uint128).max) + 1, TickMath.MAX_SQRT_RATIO - 1);

        // And: Position is single sided in token1.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, TickMath.MIN_TICK, tickCurrent));

        // And: Ticks don't overflow (invariant Uniswap).
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getSwapParams().
        // Then: Function overflows.
        vm.expectRevert(stdError.arithmeticError);
        rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);
    }

    function testFuzz_Success_getSwapParams_SingleSidedToken1(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_RATIO, type(uint128).max);

        // And: Position is single sided in token1.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, TickMath.MIN_TICK, tickCurrent));

        // And: Ticks don't overflow (invariant Uniswap).
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getSwapParams().
        (bool zeroToOne, uint256 amountIn, uint256 amountOut,) =
            rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is true.
        assertTrue(zeroToOne);

        // And: amountIn is equal to amount0.
        assertEq(amountIn, amount0);

        // And: amountOut is correct.
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountOutExpected = NoSlippageSwapMath._getAmountOut(position.sqrtPriceX96, true, amount0, fee);
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getSwapParams_currentRatioSmallerThanTarget(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        uint256 sqrtPriceX96Min = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK + 1);
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, sqrtPriceX96Min, type(uint128).max);

        // And: Position is in range.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, tickCurrent - 1));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // And: No overflow due to enormous amounts.
        // ToDo: Check opposite: loss of precision if it gives issues.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (position.sqrtPriceX96 ** 2 > UniswapV3Logic.Q192) {
                amount0 = uint128(
                    bound(
                        amount0, 0, FullMath.mulDiv(type(uint256).max, UniswapV3Logic.Q192, position.sqrtPriceX96 ** 2)
                    )
                );
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(amount0, position.sqrtPriceX96 ** 2, UniswapV3Logic.Q192);
            amount1 = uint128(bound(amount1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + amount1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(amount1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = NoSlippageSwapMath._getTargetRatio(
            position.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.newLowerTick),
            TickMath.getSqrtRatioAtTick(position.newUpperTick)
        );
        vm.assume(currentRatio < targetRatio);

        // When: Calling getSwapParams().
        (bool zeroToOne, uint256 amountIn, uint256 amountOut,) =
            rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is true.
        assertTrue(zeroToOne);

        // And: amountOut is correct.
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        {
            uint256 denominator = 1e18 + targetRatio * fee / (1e18 - fee);
            uint256 amountOutExpected = (targetRatio - currentRatio) * totalValueInToken1 / denominator;
            assertEq(amountOut, amountOutExpected);
        }

        // And: amountIn is correct.
        uint256 amountInExpected = NoSlippageSwapMath._getAmountIn(position.sqrtPriceX96, true, amountOut, fee);
        assertEq(amountIn, amountInExpected);
    }

    function testFuzz_Success_getSwapParams_currentRatioBiggerThanTarget(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        uint256 sqrtPriceX96Min = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK + 1);
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, sqrtPriceX96Min, type(uint128).max);

        // And: Position is in range.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.newUpperTick = int24(bound(position.newUpperTick, tickCurrent + 1, TickMath.MAX_TICK));
        position.newLowerTick = int24(bound(position.newLowerTick, TickMath.MIN_TICK, tickCurrent - 1));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.newLowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.newUpperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // And: No overflow due to enormous amounts.
        // ToDo: Check opposite: loss of precision if it gives issues.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (position.sqrtPriceX96 ** 2 > UniswapV3Logic.Q192) {
                amount0 = uint128(
                    bound(
                        amount0, 0, FullMath.mulDiv(type(uint256).max, UniswapV3Logic.Q192, position.sqrtPriceX96 ** 2)
                    )
                );
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(amount0, position.sqrtPriceX96 ** 2, UniswapV3Logic.Q192);
            amount1 = uint128(bound(amount1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + amount1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(amount1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = NoSlippageSwapMath._getTargetRatio(
            position.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.newLowerTick),
            TickMath.getSqrtRatioAtTick(position.newUpperTick)
        );
        vm.assume(currentRatio >= targetRatio);

        // When: Calling getSwapParams().
        (bool zeroToOne, uint256 amountIn, uint256 amountOut,) =
            rebalancer.getSwapParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is true.
        assertFalse(zeroToOne);

        // And: amountOut is correct.
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        {
            uint256 denominator = 1e18 - targetRatio * fee / 1e18;
            uint256 amountInExpected = (currentRatio - targetRatio) * totalValueInToken1 / denominator;
            assertEq(amountIn, amountInExpected);
        }

        // And: amountIn is correct.
        uint256 amountOutExpected = NoSlippageSwapMath._getAmountOut(position.sqrtPriceX96, false, amountIn, fee);
        assertEq(amountOut, amountOutExpected);
    }
}
