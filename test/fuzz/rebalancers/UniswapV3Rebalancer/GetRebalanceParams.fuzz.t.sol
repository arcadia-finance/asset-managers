/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/LiquidityAmounts.sol";
import { RebalanceLogic } from "../../../../src/rebalancers/uniswap-v3/libraries/RebalanceLogic.sol";
import { PricingLogic } from "../../../../src/rebalancers/uniswap-v3/libraries/PricingLogic.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getRebalanceParams" of contract "UniswapV3Rebalancer".
 */
contract GetRebalanceParams_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
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
    function testFuzz_Revert_getRebalanceParams_SingleSidedToken0_OverflowSqrtPriceX96(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is bigger than type(uint128).max -> overflow.
        position.sqrtPriceX96 = bound(
            position.sqrtPriceX96,
            uint256(type(uint128).max) + 1,
            TickMath.getSqrtRatioAtTick(TickMath.MAX_TICK - 1) - 1
        );

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.lowerTick = int24(bound(position.lowerTick, tickCurrent + 1, TickMath.MAX_TICK - 1));
        position.upperTick = int24(bound(position.upperTick, position.lowerTick + 1, TickMath.MAX_TICK));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getRebalanceParams().
        // Then: Function overflows.
        vm.expectRevert(stdError.arithmeticError);
        rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);
    }

    function testFuzz_Success_getRebalanceParams_SingleSidedToken0(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, TickMath.MIN_SQRT_RATIO, type(uint128).max);

        // And: Position is single sided in token0.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.lowerTick = int24(bound(position.lowerTick, tickCurrent + 1, TickMath.MAX_TICK - 1));
        position.upperTick = int24(bound(position.upperTick, position.lowerTick + 1, TickMath.MAX_TICK));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // Calculate amountOutExpected (necessary for liquidity check).
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountOutExpected = RebalanceLogic._getAmountOut(position.sqrtPriceX96, false, amount1, fee);
        uint256 balance0 = amount0 + amountOutExpected;

        // And: liquidity doesn't overflow.
        if (position.sqrtRatioLower > FixedPoint96.Q96) {
            vm.assume(position.sqrtRatioUpper < type(uint256).max / position.sqrtRatioLower * FixedPoint96.Q96);
        }
        uint256 intermediate = FullMath.mulDiv(position.sqrtRatioLower, position.sqrtRatioUpper, FixedPoint96.Q96);
        if (intermediate > (position.sqrtRatioUpper - position.sqrtRatioLower)) {
            vm.assume(balance0 < type(uint256).max / intermediate * (position.sqrtRatioUpper - position.sqrtRatioLower));
        }
        uint256 liquidity = FullMath.mulDiv(balance0, intermediate, position.sqrtRatioUpper - position.sqrtRatioLower);
        vm.assume(liquidity < type(uint128).max);

        // When: Calling getRebalanceParams().
        (, bool zeroToOne,, uint256 amountIn, uint256 amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is false.
        assertFalse(zeroToOne);

        // And: amountIn is equal to amount1.
        uint256 amountInitiatorFee_ = amount1 * initiatorFee / 1e18;
        assertEq(amountIn, amount1 - amountInitiatorFee_);

        // And: amountOut is correct.
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Revert_getRebalanceParams_SingleSidedToken1_OverflowSqrtPriceX96(
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
        position.upperTick = int24(bound(position.upperTick, TickMath.MIN_TICK, tickCurrent));

        // And: Ticks don't overflow (invariant Uniswap).
        position.lowerTick = int24(bound(position.lowerTick, TickMath.MIN_TICK, TickMath.MAX_TICK));

        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE (invariant).
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // When: Calling getRebalanceParams().
        // Then: Function overflows.
        vm.expectRevert(stdError.arithmeticError);
        rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);
    }

    function testFuzz_Success_getRebalanceParams_SingleSidedToken1(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        position.sqrtPriceX96 =
            bound(position.sqrtPriceX96, TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK + 2), type(uint128).max);

        // And: Position is single sided in token1.
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
        position.upperTick = int24(bound(position.upperTick, TickMath.MIN_TICK + 1, tickCurrent));
        position.lowerTick = int24(bound(position.lowerTick, TickMath.MIN_TICK, position.upperTick - 1));
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // Calculate amountOutExpected (necessary for liquidity check).
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountOutExpected = RebalanceLogic._getAmountOut(position.sqrtPriceX96, true, amount0, fee);
        uint256 balance1 = amount1 + amountOutExpected;

        // And: liquidity doesn't overflow.
        if (FixedPoint96.Q96 > (position.sqrtRatioUpper - position.sqrtRatioLower)) {
            vm.assume(
                balance1 < type(uint256).max / FixedPoint96.Q96 * (position.sqrtRatioUpper - position.sqrtRatioLower)
            );
        }
        uint256 liquidity =
            FullMath.mulDiv(balance1, FixedPoint96.Q96, position.sqrtRatioUpper - position.sqrtRatioLower);
        vm.assume(liquidity < type(uint128).max);

        // When: Calling getRebalanceParams().
        (, bool zeroToOne,, uint256 amountIn, uint256 amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is true.
        assertTrue(zeroToOne);

        // And: amountIn is equal to amount0.
        uint256 amountInitiatorFee_ = amount0 * initiatorFee / 1e18;
        assertEq(amountIn, amount0 - amountInitiatorFee_);

        // And: amountOut is correct.
        assertEq(amountOut, amountOutExpected);
    }

    function testFuzz_Success_getRebalanceParams_currentRatioSmallerThanTarget(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        {
            uint256 sqrtPriceX96Min = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK + 1);
            position.sqrtPriceX96 = bound(position.sqrtPriceX96, sqrtPriceX96Min, type(uint128).max);
        }

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
            position.upperTick = int24(bound(position.upperTick, tickCurrent + 1, TickMath.MAX_TICK));
            position.lowerTick = int24(bound(position.lowerTick, TickMath.MIN_TICK, tickCurrent - 1));
            position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
            position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);
        }

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // And: No overflow due to enormous amounts.
        // ToDo: Check opposite: loss of precision if it gives issues.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (position.sqrtPriceX96 ** 2 > PricingLogic.Q192) {
                amount0 = uint128(
                    bound(amount0, 0, FullMath.mulDiv(type(uint256).max, PricingLogic.Q192, position.sqrtPriceX96 ** 2))
                );
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(amount0, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            amount1 = uint128(bound(amount1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + amount1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(amount1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = RebalanceLogic._getTargetRatio(
            position.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick)
        );
        vm.assume(currentRatio < targetRatio);

        // Calculate balance1 expected (necessary for liquidity check).
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountOutExpected;
        {
            uint256 denominator = 1e18 + targetRatio * fee / (1e18 - fee);
            amountOutExpected = (targetRatio - currentRatio) * totalValueInToken1 / denominator;
        }

        // And: liquidity doesn't overflow (we only check on liquidity1 as both should be equal).
        {
            uint256 balance1 = amount1 + amountOutExpected;
            if (FixedPoint96.Q96 > (position.sqrtPriceX96 - position.sqrtRatioLower)) {
                vm.assume(
                    balance1 < type(uint256).max / FixedPoint96.Q96 * (position.sqrtPriceX96 - position.sqrtRatioLower)
                );
            }
            uint256 liquidity =
                FullMath.mulDiv(balance1, FixedPoint96.Q96, position.sqrtPriceX96 - position.sqrtRatioLower);
            vm.assume(liquidity < type(uint128).max);
        }

        // When: Calling getRebalanceParams().
        (, bool zeroToOne,, uint256 amountIn, uint256 amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is true.
        assertTrue(zeroToOne);

        // And: amountOut is correct.
        assertEq(amountOut, amountOutExpected);

        // And: amountIn is correct.
        uint256 amountInWithFee = RebalanceLogic._getAmountIn(position.sqrtPriceX96, true, amountOut, fee);
        uint256 amountInitiatorFee_ = amountInWithFee * initiatorFee / 1e18;
        assertEq(amountIn, amountInWithFee - amountInitiatorFee_);
    }

    function testFuzz_Success_getRebalanceParams_currentRatioBiggerThanTarget(
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amount0,
        uint128 amount1,
        uint256 initiatorFee
    ) public {
        // Given: sqrtPriceX96 is smaller than type(uint128).max (no overflow).
        {
            uint256 sqrtPriceX96Min = TickMath.getSqrtRatioAtTick(TickMath.MIN_TICK + 1);
            position.sqrtPriceX96 = bound(position.sqrtPriceX96, sqrtPriceX96Min, type(uint128).max);
        }

        // And: Position is in range.
        {
            int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96));
            position.upperTick = int24(bound(position.upperTick, tickCurrent + 1, TickMath.MAX_TICK));
            position.lowerTick = int24(bound(position.lowerTick, TickMath.MIN_TICK, tickCurrent - 1));
            position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(position.lowerTick);
            position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(position.upperTick);
        }

        // And: fee is smaller than MAX_INITIATOR_FEE.
        initiatorFee = bound(initiatorFee, 0, MAX_INITIATOR_FEE);
        position.fee = uint24(bound(position.fee, 0, (MAX_INITIATOR_FEE - initiatorFee) / 1e12));

        // And: No overflow due to enormous amounts.
        // ToDo: Check opposite: loss of precision if it gives issues.
        uint256 totalValueInToken1;
        uint256 currentRatio;
        {
            if (position.sqrtPriceX96 ** 2 > PricingLogic.Q192) {
                amount0 = uint128(
                    bound(amount0, 0, FullMath.mulDiv(type(uint256).max, PricingLogic.Q192, position.sqrtPriceX96 ** 2))
                );
            }
            uint256 token0ValueInToken1 = FullMath.mulDiv(amount0, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            amount1 = uint128(bound(amount1, 0, type(uint256).max - token0ValueInToken1));
            totalValueInToken1 = token0ValueInToken1 + amount1;
            vm.assume(totalValueInToken1 > 0);
            currentRatio = uint256(amount1) * 1e18 / totalValueInToken1;
        }

        // And: Current ratio is lower than target ratio.
        uint256 targetRatio = RebalanceLogic._getTargetRatio(
            position.sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(position.lowerTick),
            TickMath.getSqrtRatioAtTick(position.upperTick)
        );
        vm.assume(currentRatio >= targetRatio);

        // Calculate balance1 expected (necessary for liquidity check).
        uint256 fee = initiatorFee + uint256(position.fee) * 1e12;
        uint256 amountInWithFee;
        {
            uint256 denominator = 1e18 - targetRatio * fee / 1e18;
            amountInWithFee = (currentRatio - targetRatio) * totalValueInToken1 / denominator;
        }

        // And: liquidity doesn't overflow (we only check on liquidity1 as both should be equal).
        {
            uint256 balance1 = amount1 - amountInWithFee;
            if (FixedPoint96.Q96 > (position.sqrtPriceX96 - position.sqrtRatioLower)) {
                vm.assume(
                    balance1 < type(uint256).max / FixedPoint96.Q96 * (position.sqrtPriceX96 - position.sqrtRatioLower)
                );
            }
            uint256 liquidity =
                FullMath.mulDiv(balance1, FixedPoint96.Q96, position.sqrtPriceX96 - position.sqrtRatioLower);
            vm.assume(liquidity < type(uint128).max);
        }

        // When: Calling getRebalanceParams().
        (, bool zeroToOne,, uint256 amountIn, uint256 amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);

        // Then: zeroToOne is false.
        assertFalse(zeroToOne);

        // And: amountIn is correct.
        {
            uint256 amountInitiatorFee_ = amountInWithFee * initiatorFee / 1e18;
            assertEq(amountIn, amountInWithFee - amountInitiatorFee_);
        }

        // And: amountOut is correct.
        uint256 amountOutExpected = RebalanceLogic._getAmountOut(position.sqrtPriceX96, false, amountInWithFee, fee);
        assertEq(amountOut, amountOutExpected);
    }
}
