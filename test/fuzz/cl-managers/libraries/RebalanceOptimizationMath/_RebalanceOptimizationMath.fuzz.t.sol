/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPoint96 } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { RebalanceOptimizationMath } from "../../../../../src/cl-managers/libraries/RebalanceOptimizationMath.sol";
import {
    RebalanceOptimizationMathExtension
} from "../../../../utils/extensions/RebalanceOptimizationMathExtension.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "RebalanceOptimizationMath" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract RebalanceOptimizationMath_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_POOL_FEE = 100_000;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    struct SwapParams {
        bool zeroToOne;
        uint256 fee;
        uint128 usableLiquidity;
        uint160 sqrtPriceOld;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtRatioLower;
        uint160 sqrtRatioUpper;
        uint256 amount0;
        uint256 amount1;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalanceOptimizationMathExtension internal optimizationMath;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        optimizationMath = new RebalanceOptimizationMathExtension();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function givenValidSwapParams(SwapParams memory params, bool zeroToOne) internal pure {
        params.zeroToOne = zeroToOne;
        givenValidRange(params, TickMath.MIN_TICK, TickMath.MAX_TICK);
        params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, params.sqrtRatioLower + 1, params.sqrtRatioUpper - 1));
    }

    function givenValidSwapParamsOutOfRange(SwapParams memory params, bool zeroToOne) internal pure {
        params.zeroToOne = zeroToOne;
        if (zeroToOne) {
            givenValidRange(params, TickMath.MIN_TICK, TickMath.MAX_TICK - 1);
            params.sqrtPriceOld =
                uint160(bound(params.sqrtPriceOld, params.sqrtRatioUpper + 1, TickMath.MAX_SQRT_PRICE));
        } else {
            givenValidRange(params, TickMath.MIN_TICK + 1, TickMath.MAX_TICK);
            params.sqrtPriceOld =
                uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE, params.sqrtRatioLower - 1));
        }
    }

    function givenAmountOutToBoundAtMost(SwapParams memory params, uint256 maxAmountOut) internal pure {
        if (params.zeroToOne) {
            uint256 maxSqrtPriceOld = params.sqrtRatioUpper
                + FullMath.mulDivRoundingUp(maxAmountOut + 1, FixedPoint96.Q96, params.usableLiquidity) - 1;
            if (maxSqrtPriceOld > TickMath.MAX_SQRT_PRICE) maxSqrtPriceOld = TickMath.MAX_SQRT_PRICE;
            params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, params.sqrtRatioUpper + 1, maxSqrtPriceOld));
        } else {
            uint256 numerator = uint256(params.usableLiquidity) << FixedPoint96.RESOLUTION;
            uint256 minSqrtPriceOld = numerator / (numerator / params.sqrtRatioLower + maxAmountOut + 1) + 1;
            if (minSqrtPriceOld < TickMath.MIN_SQRT_PRICE) minSqrtPriceOld = TickMath.MIN_SQRT_PRICE;
            params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, minSqrtPriceOld, params.sqrtRatioLower - 1));
        }
    }

    function givenValidNormalizationParams(SwapParams memory params) internal pure {
        givenValidRange(params, TickMath.MIN_TICK, TickMath.MAX_TICK);
        params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper));
    }

    function givenValidRange(SwapParams memory params, int24 minTick, int24 maxTick) internal pure {
        params.fee = bound(params.fee, 0, MAX_POOL_FEE);
        params.usableLiquidity = uint128(bound(params.usableLiquidity, 1, type(uint128).max));
        params.tickLower = int24(bound(params.tickLower, minTick, maxTick - 1));
        params.tickUpper = int24(bound(params.tickUpper, params.tickLower + 1, maxTick));
        params.sqrtRatioLower = TickMath.getSqrtPriceAtTick(params.tickLower);
        params.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(params.tickUpper);
    }

    function givenValidBalances(SwapParams memory params, bool liquidity0Exceeds) internal pure {
        (uint256 maxAmount0, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        {
            (uint256 positionAmount0, uint256 positionAmount1) = LiquidityAmounts.getAmountsForLiquidity(
                params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper, type(uint128).max
            );
            if (positionAmount0 < maxAmount0) maxAmount0 = positionAmount0;
            if (positionAmount1 < maxAmount1) maxAmount1 = positionAmount1;
        }

        if (liquidity0Exceeds) {
            params.amount0 = bound(params.amount0, 0, maxAmount0);
            (uint256 liquidity0,) = getLiquidities(params, params.sqrtPriceOld, params.amount0, 0);
            (, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper, uint128(liquidity0)
            );
            params.amount1 = bound(params.amount1, 0, amount1 < maxAmount1 ? amount1 : maxAmount1);
        } else {
            params.amount1 = bound(params.amount1, 0, maxAmount1);
            (, uint256 liquidity1) = getLiquidities(params, params.sqrtPriceOld, 0, params.amount1);
            (uint256 amount0,) = LiquidityAmounts.getAmountsForLiquidity(
                params.sqrtPriceOld, params.sqrtRatioLower, params.sqrtRatioUpper, uint128(liquidity1)
            );
            params.amount0 = bound(params.amount0, 0, amount0 < maxAmount0 ? amount0 : maxAmount0);
        }
    }

    function givenValidBalancesBeyondMargin(SwapParams memory params, bool liquidity0Exceeds) internal pure {
        givenValidBalances(params, liquidity0Exceeds);

        (uint256 liquidity0, uint256 liquidity1) =
            getLiquidities(params, params.sqrtPriceOld, params.amount0, params.amount1);
        uint256 margin = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(
                params.usableLiquidity,
                (1 << 160) + 2 * uint256(params.sqrtPriceOld),
                uint256(params.sqrtRatioUpper - params.sqrtPriceOld) << 96
            ),
            params.sqrtRatioUpper,
            uint256(params.sqrtPriceOld - params.sqrtRatioLower) << 96
        );
        margin += params.amount0 / (params.sqrtRatioUpper - params.sqrtPriceOld) + 4;
        vm.assume(liquidity0Exceeds ? liquidity0 > liquidity1 + margin : liquidity1 > liquidity0 + margin);
    }

    function getAmount1OutWithSlippage(SwapParams memory params) internal view returns (uint256 amountOut) {
        amountOut = optimizationMath.getAmount1OutWithSlippage(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );
    }

    function getAmount0OutWithSlippage(SwapParams memory params) internal view returns (uint256 amountOut) {
        amountOut = optimizationMath.getAmount0OutWithSlippage(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );
    }

    function getSqrtPrice(SwapParams memory params) internal view returns (uint160 sqrtPriceNew) {
        sqrtPriceNew = optimizationMath.getSqrtPrice(
            params.zeroToOne,
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );
    }

    function getQuadraticCoefficients(SwapParams memory params)
        internal
        view
        returns (int256 quadraticCoefficient, int256 linearCoefficient, int256 constantCoefficient)
    {
        (quadraticCoefficient, linearCoefficient, constantCoefficient) = optimizationMath.getQuadraticCoefficients(
            params.zeroToOne,
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );
    }

    function getNormalizedParameters(SwapParams memory params)
        internal
        view
        returns (
            uint256 amount0Normalized,
            uint256 amount1Normalized,
            uint256 sqrtRatioLowerNormalized,
            uint256 sqrtRatioUpperInverseNormalized
        )
    {
        (
            amount0Normalized, amount1Normalized, sqrtRatioLowerNormalized, sqrtRatioUpperInverseNormalized
        ) =
            optimizationMath.getNormalizedParameters(
                params.usableLiquidity,
                params.sqrtPriceOld,
                params.sqrtRatioLower,
                params.sqrtRatioUpper,
                params.amount0,
                params.amount1
            );
    }

    function getMaxAmounts(uint256 usableLiquidity, uint256 sqrtPrice)
        internal
        pure
        returns (uint256 maxAmount0, uint256 maxAmount1)
    {
        maxAmount0 = FullMath.mulDiv(usableLiquidity, 1 << 156, sqrtPrice);
        maxAmount1 = FullMath.mulDiv(usableLiquidity, sqrtPrice, 1 << 36);
    }

    function getOverflowAmounts(uint256 usableLiquidity, uint256 sqrtPrice)
        internal
        pure
        returns (uint256 minAmount0, uint256 maxAmount0, uint256 minAmount1, uint256 maxAmount1)
    {
        minAmount0 = FullMath.mulDivRoundingUp(
            RebalanceOptimizationMath.MAX_NORMALIZED + 1, usableLiquidity, sqrtPrice << 96
        );
        maxAmount0 = FullMath.mulDiv(type(uint256).max, usableLiquidity, sqrtPrice << 96);
        minAmount1 = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(RebalanceOptimizationMath.MAX_NORMALIZED + 1, sqrtPrice, 1 << 160),
            usableLiquidity,
            1 << 128
        );
        maxAmount1 = FullMath.mulDiv(FullMath.mulDiv(type(uint256).max, sqrtPrice, 1 << 160), usableLiquidity, 1 << 128);
    }

    function getSwapToBound(SwapParams memory params) internal pure returns (uint256 amountIn, uint256 amountOut) {
        if (params.zeroToOne) {
            amountIn = FullMath.mulDivRoundingUp(
                SqrtPriceMath.getAmount0Delta(params.sqrtRatioUpper, params.sqrtPriceOld, params.usableLiquidity, true),
                1e6,
                1e6 - params.fee
            );
            amountOut = SqrtPriceMath.getAmount1Delta(
                params.sqrtRatioUpper, params.sqrtPriceOld, params.usableLiquidity, false
            );
        } else {
            amountIn = FullMath.mulDivRoundingUp(
                SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, params.sqrtRatioLower, params.usableLiquidity, true),
                1e6,
                1e6 - params.fee
            );
            amountOut = SqrtPriceMath.getAmount0Delta(
                params.sqrtPriceOld, params.sqrtRatioLower, params.usableLiquidity, false
            );
        }
    }

    function getAmountInForAmountOut(SwapParams memory params, uint256 amountOut)
        internal
        pure
        returns (uint160 sqrtPriceNew, uint256 amountIn)
    {
        sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            params.sqrtPriceOld, params.usableLiquidity, amountOut, params.zeroToOne
        );
        uint256 amountInLessFee = params.zeroToOne
            ? SqrtPriceMath.getAmount0Delta(sqrtPriceNew, params.sqrtPriceOld, params.usableLiquidity, true)
            : SqrtPriceMath.getAmount1Delta(params.sqrtPriceOld, sqrtPriceNew, params.usableLiquidity, true);
        amountIn = amountInLessFee + FullMath.mulDivRoundingUp(amountInLessFee, params.fee, 1e6 - params.fee);
    }

    function getAmountOutForAmountIn(SwapParams memory params, uint256 amountIn)
        internal
        pure
        returns (uint256 amountOut)
    {
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromInput(
            params.sqrtPriceOld,
            params.usableLiquidity,
            FullMath.mulDiv(amountIn, 1e6 - params.fee, 1e6),
            params.zeroToOne
        );
        amountOut = params.zeroToOne
            ? SqrtPriceMath.getAmount1Delta(sqrtPriceNew, params.sqrtPriceOld, params.usableLiquidity, false)
            : SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, sqrtPriceNew, params.usableLiquidity, false);
    }

    function getLiquidities(SwapParams memory params, uint160 sqrtPrice, uint256 balance0, uint256 balance1)
        internal
        pure
        returns (uint256 liquidity0, uint256 liquidity1)
    {
        liquidity0 = type(uint256).max;
        if (sqrtPrice < params.sqrtRatioUpper) {
            uint160 sqrtPriceLower = sqrtPrice > params.sqrtRatioLower ? sqrtPrice : params.sqrtRatioLower;
            uint256 intermediate = FullMath.mulDiv(sqrtPriceLower, params.sqrtRatioUpper, FixedPoint96.Q96);
            uint256 width = params.sqrtRatioUpper - sqrtPriceLower;
            if (intermediate <= width || balance0 <= FullMath.mulDiv(type(uint256).max, width, intermediate)) {
                liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, params.sqrtRatioUpper, balance0);
            }
        }
        liquidity1 = type(uint256).max;
        if (sqrtPrice > params.sqrtRatioLower) {
            uint160 sqrtPriceUpper = sqrtPrice < params.sqrtRatioUpper ? sqrtPrice : params.sqrtRatioUpper;
            uint256 width = sqrtPriceUpper - params.sqrtRatioLower;
            if (width >= FixedPoint96.Q96 || balance1 <= FullMath.mulDiv(type(uint256).max, width, FixedPoint96.Q96)) {
                liquidity1 = LiquidityAmounts.getLiquidityForAmount1(params.sqrtRatioLower, sqrtPriceUpper, balance1);
            }
        }
    }

    function getLiquiditiesAfterMove(SwapParams memory params, uint160 sqrtPrice, bool favorTokenIn)
        internal
        pure
        returns (uint256 liquidityIn, uint256 liquidityOut)
    {
        uint256 balance0;
        uint256 balance1;
        {
            uint256 amountInLessFee;
            uint256 amountOut;
            if (params.zeroToOne) {
                amountInLessFee = SqrtPriceMath.getAmount0Delta(
                    sqrtPrice, params.sqrtPriceOld, params.usableLiquidity, !favorTokenIn
                );
                amountOut = SqrtPriceMath.getAmount1Delta(
                    sqrtPrice, params.sqrtPriceOld, params.usableLiquidity, !favorTokenIn
                );
            } else {
                amountInLessFee = SqrtPriceMath.getAmount1Delta(
                    params.sqrtPriceOld, sqrtPrice, params.usableLiquidity, !favorTokenIn
                );
                amountOut = SqrtPriceMath.getAmount0Delta(
                    params.sqrtPriceOld, sqrtPrice, params.usableLiquidity, !favorTokenIn
                );
            }
            uint256 amountIn = favorTokenIn
                ? FullMath.mulDiv(amountInLessFee, 1e6, 1e6 - params.fee)
                : FullMath.mulDivRoundingUp(amountInLessFee, 1e6, 1e6 - params.fee);
            (balance0, balance1) = params.zeroToOne
                ? (FixedPointMathLib.zeroFloorSub(params.amount0, amountIn), params.amount1 + amountOut)
                : (params.amount0 + amountOut, FixedPointMathLib.zeroFloorSub(params.amount1, amountIn));
        }

        (uint256 liquidity0, uint256 liquidity1) = getLiquidities(params, sqrtPrice, balance0, balance1);
        if (params.zeroToOne == favorTokenIn) {
            liquidity0 = mulDivRoundingUpSaturating(
                balance0,
                FullMath.mulDivRoundingUp(sqrtPrice, params.sqrtRatioUpper, FixedPoint96.Q96),
                params.sqrtRatioUpper - sqrtPrice
            );
        } else {
            liquidity1 = mulDivRoundingUpSaturating(balance1, FixedPoint96.Q96, sqrtPrice - params.sqrtRatioLower);
        }
        (liquidityIn, liquidityOut) = params.zeroToOne ? (liquidity0, liquidity1) : (liquidity1, liquidity0);
    }

    function getLiquidityForAmountOut(SwapParams memory params, uint256 amountOut)
        internal
        pure
        returns (bool valid, uint256 liquidity, uint256 liquidityOut)
    {
        (uint160 sqrtPrice, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        valid = amountIn <= (params.zeroToOne ? params.amount0 : params.amount1) + 2
            && (params.zeroToOne ? sqrtPrice >= params.sqrtRatioLower : sqrtPrice <= params.sqrtRatioUpper);
        (uint256 balance0, uint256 balance1) = params.zeroToOne
            ? (FixedPointMathLib.zeroFloorSub(params.amount0, amountIn), params.amount1 + amountOut)
            : (params.amount0 + amountOut, FixedPointMathLib.zeroFloorSub(params.amount1, amountIn));
        (uint256 liquidity0, uint256 liquidity1) = getLiquidities(params, sqrtPrice, balance0, balance1);
        liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        liquidityOut = params.zeroToOne ? liquidity1 : liquidity0;
    }

    function getOptimalLiquidity(SwapParams memory params)
        internal
        pure
        returns (uint256 liquidity, uint160 sqrtPrice)
    {
        uint256 low;
        uint256 high = params.zeroToOne
            ? SqrtPriceMath.getAmount1Delta(params.sqrtRatioLower, params.sqrtPriceOld, params.usableLiquidity, false)
            : SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, params.sqrtRatioUpper, params.usableLiquidity, false);
        bool valid;
        (valid,,) = getLiquidityForAmountOut(params, high);
        if (!valid) {
            while (high - low > 1) {
                uint256 middle = (low + high) / 2;
                (valid,,) = getLiquidityForAmountOut(params, middle);
                if (valid) low = middle;
                else high = middle;
            }
            high = low;
            low = 0;
        }

        uint256 amountOut;
        uint256 liquidityOut;
        (, liquidity, liquidityOut) = getLiquidityForAmountOut(params, 0);
        if (liquidityOut <= liquidity) {
            (, liquidity, liquidityOut) = getLiquidityForAmountOut(params, high);
            if (liquidityOut <= liquidity) {
                amountOut = high;
            } else {
                while (high - low > 1) {
                    uint256 middle = (low + high) / 2;
                    (, liquidity, liquidityOut) = getLiquidityForAmountOut(params, middle);
                    if (liquidityOut <= liquidity) low = middle;
                    else high = middle;
                }
                (, liquidity,) = getLiquidityForAmountOut(params, low);
                (, uint256 liquidityNext,) = getLiquidityForAmountOut(params, high);
                amountOut = liquidityNext > liquidity ? high : low;
            }
        }
        (, liquidity,) = getLiquidityForAmountOut(params, amountOut);
        (sqrtPrice,) = getAmountInForAmountOut(params, amountOut);
    }

    function getLiquidityAndTolerance(SwapParams memory params, uint256 amountOut)
        internal
        pure
        returns (uint256 liquidity, uint256 tolerance)
    {
        uint256 liquidityOut;
        (, liquidity, liquidityOut) = getLiquidityForAmountOut(params, amountOut);
        uint256 maxAmountOut = params.zeroToOne
            ? SqrtPriceMath.getAmount1Delta(params.sqrtRatioLower, params.sqrtPriceOld, params.usableLiquidity, false)
            : SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, params.sqrtRatioUpper, params.usableLiquidity, false);
        if (amountOut < maxAmountOut) {
            (,, uint256 liquidityOutNext) = getLiquidityForAmountOut(params, amountOut + 1);
            if (liquidityOutNext != type(uint256).max && liquidityOutNext > liquidityOut) {
                tolerance = liquidityOutNext - liquidityOut;
            }
        }

        (uint160 sqrtPrice, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        if (sqrtPrice < params.sqrtRatioUpper) {
            uint160 sqrtPriceLower = sqrtPrice > params.sqrtRatioLower ? sqrtPrice : params.sqrtRatioLower;
            uint256 width = params.sqrtRatioUpper - sqrtPriceLower;
            uint256 extra0 = params.zeroToOne
                ? 3
                : FullMath.mulDiv(params.usableLiquidity, FixedPoint96.Q96, sqrtPrice) / sqrtPrice + 1;
            uint256 balance0 = params.zeroToOne
                ? FixedPointMathLib.zeroFloorSub(params.amount0, amountIn)
                : params.amount0 + amountOut;
            tolerance += balance0 / width + 1
                + FullMath.mulDivRoundingUp(
                    extra0, FullMath.mulDivRoundingUp(sqrtPriceLower, params.sqrtRatioUpper, FixedPoint96.Q96), width
                );
        }
        if (sqrtPrice > params.sqrtRatioLower) {
            uint256 extra1 = params.zeroToOne ? params.usableLiquidity / FixedPoint96.Q96 + 1 : 3;
            tolerance += LiquidityAmounts.getLiquidityForAmount1(
                params.sqrtRatioLower, sqrtPrice < params.sqrtRatioUpper ? sqrtPrice : params.sqrtRatioUpper, extra1
            );
        }
        tolerance += 1;
    }

    function getSafetyBounds(SwapParams memory params)
        internal
        pure
        returns (uint256 sqrtPriceLimit, uint256 maxAmountIn)
    {
        uint256 extra;
        if (params.zeroToOne) {
            uint256 sqrtPriceStart =
                params.sqrtPriceOld < params.sqrtRatioUpper ? params.sqrtPriceOld : params.sqrtRatioUpper;
            uint256 precision = ((sqrtPriceStart - params.sqrtRatioLower) << 50) + sqrtPriceStart;
            uint256 overshoot = precision >> 145;
            sqrtPriceLimit = params.sqrtRatioLower > overshoot ? params.sqrtRatioLower - overshoot : 1;
            extra = mulDivRoundingUpSaturating(uint256(params.usableLiquidity) << 15, precision, sqrtPriceLimit);
            if (extra < type(uint256).max) extra = FullMath.mulDivRoundingUp(extra, 1, sqrtPriceLimit);
            maxAmountIn = params.amount0;
        } else {
            uint256 sqrtPriceStart =
                params.sqrtPriceOld > params.sqrtRatioLower ? params.sqrtPriceOld : params.sqrtRatioLower;
            uint256 precision = ((params.sqrtRatioUpper - sqrtPriceStart) << 50) + sqrtPriceStart;
            sqrtPriceLimit = params.sqrtRatioUpper + (precision >> 145);
            extra = FullMath.mulDivRoundingUp(params.usableLiquidity, precision, 1 << 177);
            maxAmountIn = params.amount1;
        }
        uint256 margin = extra > type(uint256).max - (1 << 64)
            ? type(uint256).max
            : mulDivRoundingUpSaturating(extra + (1 << 64), 1e6, (1e6 - params.fee) << 64);
        maxAmountIn = margin > type(uint256).max - maxAmountIn ? type(uint256).max : maxAmountIn + margin;
    }

    function getPrecisionTolerance(SwapParams memory params, uint256 optimalLiquidity, uint160 optimalSqrtPrice)
        internal
        pure
        returns (uint256 tolerance)
    {
        uint256 window =
            ((params.zeroToOne ? params.sqrtPriceOld - optimalSqrtPrice : optimalSqrtPrice - params.sqrtPriceOld) >> 95)
                + (params.sqrtPriceOld >> 145) + 2;
        uint256 lowest = type(uint256).max;
        for (uint256 i; i < 2; ++i) {
            uint256 low;
            uint256 high = window + 1;
            uint256 middle;
            uint256 liquidity;
            do {
                uint256 amountOut;
                {
                    uint160 end;
                    if ((i == 0) == params.zeroToOne) {
                        end = uint160(
                            FixedPointMathLib.min(
                                optimalSqrtPrice + middle,
                                params.zeroToOne ? params.sqrtPriceOld : params.sqrtRatioUpper
                            )
                        );
                    } else {
                        uint256 limit = params.zeroToOne ? params.sqrtRatioLower : params.sqrtPriceOld;
                        end = uint160(optimalSqrtPrice > limit + middle ? optimalSqrtPrice - middle : limit);
                    }
                    amountOut = params.zeroToOne
                        ? SqrtPriceMath.getAmount1Delta(end, params.sqrtPriceOld, params.usableLiquidity, false)
                        : SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, end, params.usableLiquidity, false);
                }
                (bool valid, uint256 liquidityAtEnd,) = getLiquidityForAmountOut(params, amountOut);
                if (valid || middle == 0) {
                    low = middle;
                    liquidity = liquidityAtEnd;
                } else {
                    high = middle;
                }
                middle = (low + high) / 2;
            } while (high - low > 1);
            if (liquidity < lowest) lowest = liquidity;
        }
        tolerance = optimalLiquidity > lowest ? optimalLiquidity - lowest : 0;
    }

    function assertQuadraticCoefficients(
        SwapParams memory params,
        int256 quadraticCoefficient,
        int256 linearCoefficient,
        int256 constantCoefficient
    ) internal pure {
        uint256 amount0Lower = FullMath.mulDiv(
            params.amount0, uint256(params.sqrtPriceOld) << 96, params.usableLiquidity
        );
        uint256 amount0Upper =
            FullMath.mulDivRoundingUp(params.amount0, uint256(params.sqrtPriceOld) << 96, params.usableLiquidity);
        {
            uint256 feeDenominator = 1e6 - params.fee;
            uint256 numerator = (params.zeroToOne ? 1e6 : feeDenominator) << 192;
            int256 lower = int256(numerator / feeDenominator + amount0Lower);
            int256 upper = int256(FixedPointMathLib.divUp(numerator, feeDenominator) + amount0Upper);
            numerator = (params.zeroToOne ? feeDenominator : 1e6) << 192;
            lower -= int256(
                FullMath.mulDivRoundingUp(numerator, params.sqrtPriceOld, feeDenominator * params.sqrtRatioUpper)
            );
            upper -= int256(FullMath.mulDiv(numerator, params.sqrtPriceOld, feeDenominator * params.sqrtRatioUpper));
            int256 tolerance = int256(1e6 / feeDenominator + 3);
            assertGe(quadraticCoefficient, lower - tolerance);
            assertLe(quadraticCoefficient, upper + tolerance);
        }
        uint256 amount1Lower;
        uint256 amount1Upper;
        {
            uint256 quotient = FullMath.mulDiv(params.amount1, 1 << 128, params.usableLiquidity);
            uint256 rest = mulmod(params.amount1, 1 << 128, params.usableLiquidity);
            uint256 remainder = FullMath.mulDiv(rest, 1 << 160, params.usableLiquidity)
                + mulmod(quotient, 1 << 160, params.sqrtPriceOld);
            amount1Lower = FullMath.mulDiv(quotient, 1 << 160, params.sqrtPriceOld) + remainder / params.sqrtPriceOld;
            amount1Upper = mulmod(rest, 1 << 160, params.usableLiquidity) == 0 && remainder % params.sqrtPriceOld == 0
                ? amount1Lower
                : amount1Lower + 1;
        }
        {
            int256 tolerance = int256(uint256(1 << 160) / params.sqrtPriceOld + 5);
            int256 lower = int256(
                FullMath.mulDiv(amount0Lower, params.sqrtPriceOld - params.sqrtRatioLower, params.sqrtPriceOld)
            )
            - int256(
                FullMath.mulDivRoundingUp(
                    amount1Upper, params.sqrtRatioUpper - params.sqrtPriceOld, params.sqrtRatioUpper
                )
            );
            int256 upper = int256(
                FullMath.mulDivRoundingUp(
                    amount0Upper, params.sqrtPriceOld - params.sqrtRatioLower, params.sqrtPriceOld
                )
            )
            - int256(FullMath.mulDiv(amount1Lower, params.sqrtRatioUpper - params.sqrtPriceOld, params.sqrtRatioUpper));
            assertGt(constantCoefficient, lower - tolerance);
            assertLt(constantCoefficient, upper + tolerance);
        }
        uint256 lowerLinear = amount0Lower
            + FullMath.mulDiv(amount0Lower, params.sqrtPriceOld - params.sqrtRatioLower, params.sqrtPriceOld)
            + FullMath.mulDiv(amount1Lower, params.sqrtPriceOld, params.sqrtRatioUpper);
        uint256 upperLinear = amount0Upper
            + FullMath.mulDivRoundingUp(amount0Upper, params.sqrtPriceOld - params.sqrtRatioLower, params.sqrtPriceOld)
            + FullMath.mulDivRoundingUp(amount1Upper, params.sqrtPriceOld, params.sqrtRatioUpper);
        {
            uint256 feeDenominator = 1e6 - params.fee;
            uint256 numerator = (params.zeroToOne ? 1e6 : feeDenominator) << 192;
            lowerLinear += FullMath.mulDiv(
                numerator, params.sqrtPriceOld - params.sqrtRatioLower, feeDenominator * params.sqrtPriceOld
            );
            upperLinear += FullMath.mulDivRoundingUp(
                numerator, params.sqrtPriceOld - params.sqrtRatioLower, feeDenominator * params.sqrtPriceOld
            );
            numerator = (params.zeroToOne ? feeDenominator : 1e6) << 192;
            lowerLinear += FullMath.mulDiv(
                numerator, params.sqrtRatioUpper - params.sqrtPriceOld, feeDenominator * params.sqrtRatioUpper
            );
            upperLinear += FullMath.mulDivRoundingUp(
                numerator, params.sqrtRatioUpper - params.sqrtPriceOld, feeDenominator * params.sqrtRatioUpper
            );
        }
        int256 toleranceLinear = int256(((amount0Upper + amount1Upper) >> 192) + (1 << 160) / params.sqrtPriceOld + 15);
        assertGe(linearCoefficient, int256(lowerLinear) - toleranceLinear);
        assertLe(linearCoefficient, int256(upperLinear) + toleranceLinear);
    }

    function mulDivRoundingUpSaturating(uint256 x, uint256 y, uint256 denominator)
        internal
        pure
        returns (uint256 result)
    {
        uint256 high;
        assembly ("memory-safe") {
            let mm := mulmod(x, y, not(0))
            let low := mul(x, y)
            high := sub(sub(mm, low), lt(mm, low))
        }
        if (high >= denominator) return type(uint256).max;
        result = FullMath.mulDiv(x, y, denominator);
        if (result < type(uint256).max && mulmod(x, y, denominator) > 0) result++;
    }
}
