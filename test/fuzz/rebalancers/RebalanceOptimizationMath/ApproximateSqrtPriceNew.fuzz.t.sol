/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_approximateSqrtPriceNew" of contract "RebalanceOptimizationMath".
 */
contract ApproximateSqrtPriceNew_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_approximateSqrtPriceNew_ZeroToOne(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given: Swap is zero to one.
        bool zeroToOne = true;

        // And: fee is smaller than 1e6 (invariant).
        fee = bound(fee, 0, 1e6 - 1);

        // And: sqrtPriceOld is within boundaries.
        sqrtPriceOld = uint160(bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MIN_SQRT_PRICE));

        // And: amountIn without slippage would not result in an amountOut that would overflow.
        amountIn = uint128(
            bound(amountIn, 0, type(uint256).max / FixedPoint96.Q96 * sqrtPriceOld / FixedPoint96.Q96 * sqrtPriceOld)
        );

        // And: amountOut without slippage would not result in an amountIn that would overflow.
        if (sqrtPriceOld > FixedPoint96.Q96) {
            amountOut = uint128(
                bound(
                    amountOut, 0, type(uint256).max / sqrtPriceOld * FixedPoint96.Q96 / sqrtPriceOld * FixedPoint96.Q96
                )
            );
        }

        // And: usableLiquidity is greater than 0.
        usableLiquidity = uint128(bound(usableLiquidity, 1, type(uint128).max));

        // sqrtPriceOld is greater than quotient (requirement for getNextSqrtPriceFromAmount1RoundingUp).
        vm.assume(uint256(amountOut) * FixedPoint96.Q96 / sqrtPriceOld <= type(uint128).max);
        usableLiquidity =
            uint128(bound(usableLiquidity, uint256(amountOut) * FixedPoint96.Q96 / sqrtPriceOld, type(uint128).max));
        vm.assume(sqrtPriceOld > FullMath.mulDivRoundingUp(amountOut, FixedPoint96.Q96, usableLiquidity));

        // When: Calling _approximateSqrtPriceNew().
        // Then: It does not revert.
        uint256 sqrtPriceNew =
            optimizationMath.approximateSqrtPriceNew(zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn, amountOut);

        // And: sqrtPriceNew is always smaller or equal than sqrtPriceOld.
        assertLe(sqrtPriceNew, sqrtPriceOld);
    }

    function testFuzz_Success_approximateSqrtPriceNew_OneToZero(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given: Swap is one to zero.
        bool zeroToOne = false;

        // And: fee is smaller than 1e6 (invariant).
        fee = bound(fee, 0, 1e6 - 1);

        // And: sqrtPriceOld is within boundaries.
        sqrtPriceOld = uint160(bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MIN_SQRT_PRICE));

        // And: amountOut without slippage would not result in an amountIn that would overflow.
        amountOut = uint128(
            bound(amountOut, 0, type(uint256).max / FixedPoint96.Q96 * sqrtPriceOld / FixedPoint96.Q96 * sqrtPriceOld)
        );

        // And: Product does not overflow (requirement for getNextSqrtPriceFromAmount0RoundingUp).
        amountOut = uint128(bound(amountOut, 0, type(uint256).max / sqrtPriceOld));
        uint256 product = uint256(amountOut) * sqrtPriceOld;

        // And: Denominator does not underflow (requirement for getNextSqrtPriceFromAmount0RoundingUp).
        usableLiquidity = uint128(bound(usableLiquidity, product / FixedPoint96.Q96, type(uint128).max));

        // And the final sqrtPriceNew is smaller than a uint160 (requirement for getNextSqrtPriceFromAmount0RoundingUp).
        uint256 numerator1 = uint256(usableLiquidity) * FixedPoint96.Q96;
        vm.assume(numerator1 > product);
        uint256 denominator = numerator1 - product;
        vm.assume(FullMath.mulDiv(numerator1, sqrtPriceOld, denominator) < type(uint160).max);

        // And: amountIn without slippage would not result in an amountOut that would overflow.
        if (sqrtPriceOld > FixedPoint96.Q96) {
            amountIn = uint128(
                bound(
                    amountIn, 0, type(uint256).max / sqrtPriceOld * FixedPoint96.Q96 / sqrtPriceOld * FixedPoint96.Q96
                )
            );
        }

        // And the final sqrtPriceNew is smaller than a uint160 (requirement for getNextSqrtPriceFromAmount1RoundingDown).
        uint256 quotient = FullMath.mulDiv(amountIn, FixedPoint96.Q96, usableLiquidity);
        vm.assume(sqrtPriceOld < type(uint256).max - quotient);
        vm.assume(sqrtPriceOld + quotient < type(uint160).max);

        // When: Calling _approximateSqrtPriceNew().
        // Then: It does not revert.
        uint256 sqrtPriceNew =
            optimizationMath.approximateSqrtPriceNew(zeroToOne, fee, usableLiquidity, sqrtPriceOld, amountIn, amountOut);

        // And: sqrtPriceNew is always greater or equal than sqrtPriceOld.
        assertGe(sqrtPriceNew, sqrtPriceOld);
    }
}
