/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { SwapMath_Fuzz_Test } from "./_SwapMath.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_approximateOptimalSwapAmounts" of contract "SwapMath".
 */
contract ApproximateOptimalSwapAmounts_SwapMath_Fuzz_Test is SwapMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SwapMath_Fuzz_Test.setUp();
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
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_RATIO, type(uint128).max - 2));
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
        }

        // And: Liquidity1 is smaller than type(uint128).max.
        {
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = swapMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );
        balance0 = amount0 - amountIn_;
        balance1 = amount1 + amountOut_;

        (uint256 lAmount0, uint256 lAmount1) =
            getLiquidityAmounts(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1);
        vm.assume(lAmount0 > 1e4 && amountIn_ != 0);
        assertApproxEqRel(balance0, lAmount0, 1e18 / 1e4);
        vm.assume(lAmount1 > 1e4 && amountOut_ != 0);
        assertApproxEqRel(balance1, lAmount1, 1e18 / 1e4);
    }

    function testFuzz_Success_approximateOptimalSwapAmounts_OneToZero(
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
        sqrtRatioLower = uint128(bound(sqrtRatioLower, TickMath.MIN_SQRT_RATIO, type(uint128).max - 2));
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
        }

        // And: Liquidity1 is smaller than type(uint128).max.
        {
            uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPrice - sqrtRatioLower);
            vm.assume(liquidity1 < type(uint128).max);
        }

        // When: Calling _approximateOptimalSwapAmounts().
        // Then: It does not revert.
        (, uint256 amountIn_, uint256 amountOut_) = swapMath.approximateOptimalSwapAmounts(
            zeroToOne, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, amountIn, amountOut, sqrtPrice
        );
        balance0 = amount0 + amountOut_;
        balance1 = amount1 - amountIn_;

        (uint256 lAmount0, uint256 lAmount1) =
            getLiquidityAmounts(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, balance0, balance1);
        vm.assume(lAmount0 > 1e4 && amountIn_ != 0);
        assertApproxEqRel(balance0, lAmount0, 1e18 / 1e4);
        vm.assume(lAmount1 > 1e4 && amountOut_ != 0);
        assertApproxEqRel(balance1, lAmount1, 1e18 / 1e4);
    }
}
