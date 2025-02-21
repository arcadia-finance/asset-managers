/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/uniswap-v3/LiquidityAmounts.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_approximateOptimalSwapAmounts" of contract "RebalanceOptimizationMath".
 */
contract ApproximateOptimalSwapAmounts_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_approximateOptimalSwapAmounts_ZeroToOne_NonZeroBalance(
        uint128 sqrtRatioLower,
        uint128 sqrtRatioUpper,
        uint128 amount0,
        uint128 amount1,
        uint128 amountIn,
        uint128 amountOut,
        uint128 sqrtPrice
    ) public {
        // Given: Swap is zero to one.
        bool zeroToOne = true;

        // And: all prices are in range and within boundaries.
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, type(uint128).max - 2));
        sqrtPrice = uint128(bound(sqrtPrice, sqrtRatioLower + 1, type(uint128).max - 1));
        sqrtRatioUpper = uint128(bound(sqrtRatioUpper, sqrtPrice + 1, type(uint128).max));

        // And: Initial balances are non zero.
        amount0 = uint128(bound(amount0, 1, type(uint128).max));
        amountIn = uint128(bound(amountIn, 0, amount0 - 1));
        amount1 = uint128(bound(amount1, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, type(uint128).max - amount1));
        uint256 balance0 = amount0 - amountIn;
        uint256 balance1 = amount1 + amountOut;

        // And: Liquidity0 is smaller than type(uint128).max.
        {
            uint256 intermediate = FullMath.mulDiv(sqrtPrice, sqrtRatioUpper, FixedPoint96.Q96);
            if (intermediate > sqrtRatioUpper - sqrtPrice) {
                vm.assume(balance0 < FullMath.mulDiv(type(uint256).max, sqrtRatioUpper - sqrtPrice, intermediate));
            }
            uint256 liquidity0 = FullMath.mulDiv(balance0, intermediate, sqrtRatioUpper - sqrtPrice);
            vm.assume(liquidity0 < type(uint128).max);

            // And: Liquidity1 is smaller than type(uint128).max.
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);

            // And: The new balances are not 0 (test-case).
            if (liquidity0 < liquidity1) {
                uint256 amount1New = SqrtPriceMath.getAmount1Delta(
                    sqrtRatioLower, sqrtPrice, LiquidityAmounts.toUint128(liquidity0), true
                );
                vm.assume(amount1New > amount1);
            }
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = optimizationMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );
        balance0 = amount0 - amountIn_;
        balance1 = amount1 + amountOut_;

        // And: The remaining balances after providing liquidity are close to zero.
        // In certain conditions, the checks will fail, but we still check for those if the transaction does not revert.
        // We do not check when:
        // - The position is almost out of range.
        // - The initial balance is very small.
        if (
            1e18 - 1e18 * uint256(sqrtRatioLower) / sqrtPrice > 1e14
                && 1e18 - 1e18 * uint256(sqrtPrice) / sqrtRatioUpper > 1e14
        ) {
            (uint256 lAmount0, uint256 lAmount1) =
                getLiquidityAmounts(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1);
            vm.assume(balance0 > 1e5);
            assertApproxEqRel(balance0, lAmount0, 1e18 / 2e1);
            vm.assume(balance1 > 1e5);
            assertApproxEqRel(balance1, lAmount1, 1e18 / 2e1);
        }
    }

    function testFuzz_Success_approximateOptimalSwapAmounts_ZeroToOne_ZeroBalance(
        uint128 sqrtRatioLower,
        uint128 sqrtRatioUpper,
        uint128 amount0,
        uint128 amount1,
        uint128 amountIn,
        uint128 amountOut,
        uint128 sqrtPrice
    ) public {
        // Given: Swap is zero to one.
        bool zeroToOne = true;

        // And: all prices are in range and within boundaries.
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, type(uint128).max - 2));
        sqrtPrice = uint128(bound(sqrtPrice, sqrtRatioLower + 1, type(uint128).max - 1));
        sqrtRatioUpper = uint128(bound(sqrtRatioUpper, sqrtPrice + 1, type(uint128).max));

        // And: Initial balances can be zero.
        amount0 = uint128(bound(amount0, 1, type(uint128).max));
        amount1 = uint128(bound(amount1, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, type(uint128).max - amount1));
        uint256 balance0 = amount0 > amountIn ? amount0 - amountIn : 0;
        uint256 balance1 = amount1 + amountOut;

        // And: Liquidity0 is smaller than type(uint128).max.
        {
            uint256 intermediate = FullMath.mulDiv(sqrtPrice, sqrtRatioUpper, FixedPoint96.Q96);
            if (intermediate > sqrtRatioUpper - sqrtPrice) {
                vm.assume(balance0 < FullMath.mulDiv(type(uint256).max, sqrtRatioUpper - sqrtPrice, intermediate));
            }
            uint256 liquidity0 = FullMath.mulDiv(balance0, intermediate, sqrtRatioUpper - sqrtPrice);
            vm.assume(liquidity0 < type(uint128).max);

            // And: Liquidity1 is smaller than type(uint128).max.
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);

            // And: The new balances are 0 (test-case).
            vm.assume(liquidity0 < liquidity1);
            uint256 amount1New =
                SqrtPriceMath.getAmount1Delta(sqrtRatioLower, sqrtPrice, LiquidityAmounts.toUint128(liquidity0), true);
            vm.assume(amount1New < amount1);
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = optimizationMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );

        // And: amountIn remains equal.
        assertEq(amountIn_, amountIn);

        // And: amountOut is reduced by 10%.
        assertEq(amountOut_, uint256(amountOut) * 9 / 10);
    }

    function testFuzz_Success_approximateOptimalSwapAmounts_OneToZero_NonZeroBalance(
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint128 amount0,
        uint128 amount1,
        uint128 amountIn,
        uint128 amountOut,
        uint160 sqrtPrice
    ) public {
        // Given: Swap is one to zero.
        bool zeroToOne = false;

        // And: all prices are in range and within boundaries.
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE * 100, type(uint128).max - 2));
        sqrtPrice = uint128(bound(sqrtPrice, sqrtRatioLower + 1, type(uint128).max - 1));
        sqrtRatioUpper = uint128(bound(sqrtRatioUpper, sqrtPrice + 1, type(uint128).max));

        // And: Initial balances are non zero.
        amount0 = uint128(bound(amount0, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, type(uint128).max - amount0));
        amount1 = uint128(bound(amount1, 1, type(uint128).max));
        amountIn = uint128(bound(amountIn, 0, amount1 - 1));
        uint256 balance0 = amount0 + amountOut;
        uint256 balance1 = amount1 - amountIn;

        // And: Liquidity0 is smaller than type(uint128).max.
        {
            uint256 intermediate = FullMath.mulDiv(sqrtPrice, sqrtRatioUpper, FixedPoint96.Q96);
            if (intermediate > sqrtRatioUpper - sqrtPrice) {
                vm.assume(balance0 < FullMath.mulDiv(type(uint256).max, sqrtRatioUpper - sqrtPrice, intermediate));
            }
            uint256 liquidity0 = FullMath.mulDiv(balance0, intermediate, sqrtRatioUpper - sqrtPrice);
            vm.assume(liquidity0 < type(uint128).max);

            // And: Liquidity1 is smaller than type(uint128).max.
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);

            // And: The new balances are not 0 (test-case).
            if (liquidity0 > liquidity1) {
                uint256 amount0New = SqrtPriceMath.getAmount0Delta(
                    sqrtPrice, sqrtRatioUpper, LiquidityAmounts.toUint128(liquidity1), true
                );
                vm.assume(amount0New > amount0);
            }
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = optimizationMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );
        balance0 = amount0 + amountOut_;
        balance1 = amount1 - amountIn_;

        // And: The remaining balances after providing liquidity are close to zero.
        // In certain conditions, the checks will not fail, but we still check for those if the transaction does not revert.
        // We do not check when:
        // - The position is almost out of range.
        // - The initial balance is very small.
        if (
            1e18 - 1e18 * uint256(sqrtRatioLower) / sqrtPrice > 1e14
                && 1e18 - 1e18 * uint256(sqrtPrice) / sqrtRatioUpper > 1e14
        ) {
            (uint256 lAmount0, uint256 lAmount1) =
                getLiquidityAmounts(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1);
            vm.assume(lAmount0 > 1e5);
            assertApproxEqRel(balance0, lAmount0, 1e18 / 1e2);
            vm.assume(lAmount1 > 1e5);
            assertApproxEqRel(balance1, lAmount1, 1e18 / 1e2);
        }
    }

    function testFuzz_Success_approximateOptimalSwapAmounts_OneToZero_ZeroBalance(
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint128 amount0,
        uint128 amount1,
        uint128 amountIn,
        uint128 amountOut,
        uint160 sqrtPrice
    ) public {
        // Given: Swap is one to zero.
        bool zeroToOne = false;

        // And: all prices are in range and within boundaries.
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_PRICE, type(uint128).max - 2));
        sqrtPrice = uint128(bound(sqrtPrice, sqrtRatioLower + 1, type(uint128).max - 1));
        sqrtRatioUpper = uint128(bound(sqrtRatioUpper, sqrtPrice + 1, type(uint128).max));

        // And: Initial balances can be zero.
        amount0 = uint128(bound(amount0, 1, type(uint128).max));
        amountOut = uint128(bound(amountOut, 0, type(uint128).max - amount0));
        amount1 = uint128(bound(amount1, 1, type(uint128).max));
        uint256 balance0 = amount0 + amountOut;
        uint256 balance1 = amount1 > amountIn ? amount1 - amountIn : 0;

        // And: Liquidity0 is smaller than type(uint128).max.
        {
            uint256 intermediate = FullMath.mulDiv(sqrtPrice, sqrtRatioUpper, FixedPoint96.Q96);
            if (intermediate > sqrtRatioUpper - sqrtPrice) {
                vm.assume(balance0 < FullMath.mulDiv(type(uint256).max, sqrtRatioUpper - sqrtPrice, intermediate));
            }
            uint256 liquidity0 = FullMath.mulDiv(balance0, intermediate, sqrtRatioUpper - sqrtPrice);
            vm.assume(liquidity0 < type(uint128).max);

            // And: Liquidity1 is smaller than type(uint128).max.
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);

            // And: The new balances are not 0 (test-case).
            vm.assume(liquidity0 > liquidity1);
            uint256 amount0New =
                SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtRatioUpper, LiquidityAmounts.toUint128(liquidity1), true);
            vm.assume(amount0New < amount0);
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = optimizationMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );

        // And: amountIn remains equal.
        assertEq(amountIn_, amountIn);

        // And: amountOut is reduced by 10%.
        assertEq(amountOut_, uint256(amountOut) * 9 / 10);
    }
}
