/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPoint96 } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_capAmount0Out" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CapAmount0Out_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_capAmount0Out_LeavesOneWei(
        SwapParams memory params,
        uint160 sqrtPriceNew,
        uint256 amountOut
    ) public view {
        // Given: A position in range and a valid nonzero token1 balance.
        givenValidSwapParams(params, false);
        params.usableLiquidity = uint128(
            bound(params.usableLiquidity, FixedPointMathLib.divUp(1 << 36, params.sqrtPriceOld), type(uint128).max)
        );
        (, uint256 maxAmount1) = getMaxAmounts(params.usableLiquidity, params.sqrtPriceOld);
        params.amount1 = bound(params.amount1, 1, maxAmount1);

        // And: sqrtPriceNew costs at most amount1 − 1.
        uint256 amountInLessFee =
            FullMath.mulDiv(FixedPointMathLib.zeroFloorSub(params.amount1, 1), 1e6 - params.fee, 1e6);
        uint256 sqrtPriceLimit =
            params.sqrtPriceOld + FullMath.mulDiv(amountInLessFee, FixedPoint96.Q96, params.usableLiquidity);
        sqrtPriceNew = uint160(
            bound(sqrtPriceNew, params.sqrtPriceOld, FixedPointMathLib.min(sqrtPriceLimit, TickMath.MAX_SQRT_PRICE))
        );

        // And: amountOut is at most the largest amountOut that reaches sqrtPriceNew.
        amountOut = bound(
            amountOut,
            0,
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, sqrtPriceNew, params.usableLiquidity, false)
        );

        // When: Calling _capAmount0Out().
        uint256 amountOutCapped = optimizationMath.capAmount0Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            sqrtPriceNew,
            params.amount1,
            amountOut
        );

        // Then: The amountOut is returned unchanged.
        assertEq(amountOutCapped, amountOut);

        // And: The pool's swap for amountOut leaves at least one wei of token1.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOutCapped);
        assertLt(amountIn, params.amount1);
    }

    function testFuzz_Success_capAmount0Out_Capped(SwapParams memory params, uint160 sqrtPriceNew, uint256 amountOut)
        public
        view
    {
        // Given: A position in range and a token1 balance below the MAX_SQRT_PRICE limit.
        givenValidSwapParams(params, false);
        params.amount1 = bound(
            params.amount1,
            1,
            FullMath.mulDivRoundingUp(
                TickMath.MAX_SQRT_PRICE - params.sqrtPriceOld, params.usableLiquidity, FixedPoint96.Q96
            )
        );

        // And: sqrtPriceNew costs at least amount1.
        uint256 amountInLessFee = FullMath.mulDiv(params.amount1 - 1, 1e6 - params.fee, 1e6);
        uint256 sqrtPriceLimit =
            params.sqrtPriceOld + FullMath.mulDiv(amountInLessFee, FixedPoint96.Q96, params.usableLiquidity);
        sqrtPriceNew = uint160(bound(sqrtPriceNew, sqrtPriceLimit + 1, TickMath.MAX_SQRT_PRICE));

        // When: Calling _capAmount0Out().
        uint256 amountOutCapped = optimizationMath.capAmount0Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            sqrtPriceNew,
            params.amount1,
            amountOut
        );

        // Then: The amountOut is capped at the largest amountOut that reaches that price.
        uint256 amountOutLimit = SqrtPriceMath.getAmount0Delta(
            params.sqrtPriceOld, uint160(sqrtPriceLimit), params.usableLiquidity, false
        );
        assertEq(amountOutCapped, FixedPointMathLib.min(amountOut, amountOutLimit));

        // And: The capped swap leaves at least one wei of token1.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOutCapped);
        assertLt(amountIn, params.amount1);
    }

    function testFuzz_Success_capAmount0Out_CappedAtLowerTick(
        SwapParams memory params,
        uint160 sqrtPriceNew,
        uint256 amountOut
    ) public view {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: A balance of token1 that pays exactly for the swap to the lower tick.
        (uint256 amountInToBound, uint256 amountOutToBound) = getSwapToBound(params);
        params.amount1 = amountInToBound;

        // And: sqrtPriceNew lies in the range.
        sqrtPriceNew = uint160(bound(sqrtPriceNew, params.sqrtRatioLower, params.sqrtRatioUpper));

        // And: amountOut reaches the lower tick, and at most sqrtPriceNew.
        amountOut = bound(
            amountOut,
            amountOutToBound,
            SqrtPriceMath.getAmount0Delta(params.sqrtPriceOld, sqrtPriceNew, params.usableLiquidity, false)
        );

        // When: Calling _capAmount0Out().
        uint256 amountOutCapped = optimizationMath.capAmount0Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            sqrtPriceNew,
            params.amount1,
            amountOut
        );

        // Then: The swap reaches the lower tick.
        assertGe(amountOutCapped, amountOutToBound);

        // And: The capped swap costs at most the token1 balance.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOutCapped);
        assertLe(amountIn, params.amount1);
    }
}
