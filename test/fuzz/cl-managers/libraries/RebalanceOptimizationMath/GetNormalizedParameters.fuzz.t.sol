/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceOptimizationMath } from "../../../../../src/cl-managers/libraries/RebalanceOptimizationMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getNormalizedParameters" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetNormalizedParameters_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_getNormalizedParameters_ZeroLiquidity(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: usableLiquidity is zero.
        params.usableLiquidity = 0;

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount0FullMulDivOverflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: amount0 * sqrtPriceOld * 2^96 / L does not fit 256 bits.
        params.amount0 = bound(
            params.amount0,
            FullMath.mulDivRoundingUp(params.usableLiquidity, 1 << 160, params.sqrtPriceOld),
            type(uint256).max
        );

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount1FullMulDivOverflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: amount0 * sqrtPriceOld * 2^96 / L fits 256 bits.
        (, uint256 maxAmount0,,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);

        // And: amount1 * 2^288 / (L * sqrtPriceOld) does not fit 256 bits.
        params.amount1 = bound(
            params.amount1,
            FullMath.mulDivRoundingUp(params.sqrtPriceOld, params.usableLiquidity, 1 << 32),
            type(uint256).max
        );

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount0Overflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: The normalized amount0 exceeds MAX_NORMALIZED.
        (uint256 minAmount0, uint256 maxAmount0,,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, minAmount0, maxAmount0);

        // And: The normalized amount1 does not exceed MAX_NORMALIZED.
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, 0, maxAmount1);

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount0JustAboveMaxNormalized(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: amount0 is the smallest balance whose normalized value exceeds MAX_NORMALIZED.
        (params.amount0,,,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);

        // And: The normalized amount1 does not exceed MAX_NORMALIZED.
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, 0, maxAmount1);

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount1Overflow(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: The normalized amount0 does not exceed MAX_NORMALIZED.
        (uint256 maxAmount0,) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);

        // And: The normalized amount1 exceeds MAX_NORMALIZED.
        (,, uint256 minAmount1, uint256 maxAmount1) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, minAmount1, maxAmount1);

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Revert_getNormalizedParameters_Amount1JustAboveMaxNormalized(SwapParams memory params) public {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: The normalized amount0 does not exceed MAX_NORMALIZED.
        (uint256 maxAmount0,) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);

        // And: amount1 is the smallest balance whose normalized value exceeds MAX_NORMALIZED.
        (,, params.amount1,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);

        // When: Calling _getNormalizedParameters().
        // Then: It should revert.
        vm.expectRevert(RebalanceOptimizationMath.Overflow.selector);
        getNormalizedParameters(params);
    }

    function testFuzz_Success_getNormalizedParameters(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: The normalized balances do not exceed MAX_NORMALIZED.
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);
        params.amount1 = bound(params.amount1, 0, maxAmount1);

        // When: Calling _getNormalizedParameters().
        (
            uint256 amount0Normalized,
            uint256 amount1Normalized,
            uint256 sqrtRatioLowerNormalized,
            uint256 sqrtRatioUpperInverseNormalized
        ) = getNormalizedParameters(params);

        // Then: amount0Normalized is amount0 * sqrtPriceOld * 2^96 / L, rounded down.
        assertEq(
            amount0Normalized,
            FullMath.mulDiv(params.amount0, uint256(params.sqrtPriceOld) << 96, params.usableLiquidity)
        );

        // And: amount1Normalized is at most amount1 * 2^288 / (L * sqrtPriceOld) rounded down, and at most ⌈2^160 / sqrtPriceOld⌉ below it.
        {
            uint256 quotient = FullMath.mulDiv(params.amount1, 1 << 128, params.usableLiquidity);
            uint256 remainder = FullMath.mulDiv(
                mulmod(params.amount1, 1 << 128, params.usableLiquidity), 1 << 160, params.usableLiquidity
            ) + mulmod(quotient, 1 << 160, params.sqrtPriceOld);
            uint256 amount1Exact =
                FullMath.mulDiv(quotient, 1 << 160, params.sqrtPriceOld) + remainder / params.sqrtPriceOld;
            assertLe(amount1Normalized, amount1Exact);
            assertLe(amount1Exact, amount1Normalized + FixedPointMathLib.divUp(1 << 160, params.sqrtPriceOld));
        }

        // And: sqrtRatioLowerNormalized is sqrtRatioLower * 2^192 / sqrtPriceOld, rounded down.
        assertEq(sqrtRatioLowerNormalized, FullMath.mulDiv(params.sqrtRatioLower, 1 << 192, params.sqrtPriceOld));

        // And: sqrtRatioUpperInverseNormalized is sqrtPriceOld * 2^192 / sqrtRatioUpper, rounded down.
        assertEq(sqrtRatioUpperInverseNormalized, FullMath.mulDiv(params.sqrtPriceOld, 1 << 192, params.sqrtRatioUpper));
    }

    function testFuzz_Success_getNormalizedParameters_Amount0AtMaxNormalized(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: sqrtPriceOld is a multiple of 2^32 if it exceeds 2^128.
        uint256 shift = params.sqrtPriceOld > type(uint128).max ? 32 : 0;
        params.sqrtPriceOld = uint160(
            bound(
                params.sqrtPriceOld >> shift,
                (params.sqrtRatioLower + (1 << shift) - 1) >> shift,
                params.sqrtRatioUpper >> shift
            ) << shift
        );

        // And: usableLiquidity is a multiple of sqrtPriceOld / 2^shift.
        uint256 divisor = params.sqrtPriceOld >> shift;
        params.usableLiquidity = uint128(bound(params.usableLiquidity, 1, type(uint128).max / divisor) * divisor);

        // And: amount0 is the largest balance whose normalized value does not exceed MAX_NORMALIZED.
        (uint256 minAmount0,,,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = minAmount0 - 1;

        // And: The normalized amount1 does not exceed MAX_NORMALIZED.
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, 0, maxAmount1);

        // When: Calling _getNormalizedParameters().
        (uint256 amount0Normalized,,,) = getNormalizedParameters(params);

        // Then: amount0Normalized equals MAX_NORMALIZED.
        assertEq(amount0Normalized, RebalanceOptimizationMath.MAX_NORMALIZED);
    }

    function testFuzz_Success_getNormalizedParameters_Amount1AtMaxNormalized(SwapParams memory params) public view {
        // Given: A position in range.
        givenValidNormalizationParams(params);

        // And: usableLiquidity is a multiple of 2^36.
        params.usableLiquidity = uint128(bound(params.usableLiquidity, 1, type(uint128).max >> 36) << 36);

        // And: The normalized amount0 does not exceed MAX_NORMALIZED.
        (uint256 maxAmount0,) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount0 = bound(params.amount0, 0, maxAmount0);

        // And: amount1 is the largest balance whose normalized value does not exceed MAX_NORMALIZED.
        (,, uint256 minAmount1,) = getOverflowAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = minAmount1 - 1;

        // When: Calling _getNormalizedParameters().
        (, uint256 amount1Normalized,,) = getNormalizedParameters(params);

        // Then: amount1Normalized equals MAX_NORMALIZED.
        assertEq(amount1Normalized, RebalanceOptimizationMath.MAX_NORMALIZED);
    }
}
