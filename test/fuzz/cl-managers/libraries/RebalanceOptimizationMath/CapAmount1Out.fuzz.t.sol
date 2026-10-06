/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_capAmount1Out" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CapAmount1Out_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_capAmount1Out_LeavesOneWei(
        SwapParams memory params,
        uint160 sqrtPriceNew,
        uint256 amountOut
    ) public view {
        // Given: A position in range, and a balance of token0 whose net amountIn times sqrtPriceOld fits 256 bits.
        givenValidSwapParams(params, true);
        params.amount0 = bound(params.amount0, 0, type(uint256).max / params.sqrtPriceOld);

        // And: sqrtPriceNew costs at most amount0 − 1, so lies at or above the pool's price for the net amountIn of amount0 − 1.
        uint256 amountInLessFee = FixedPointMathLib.zeroFloorSub(params.amount0, 1) * (1e6 - params.fee) / 1e6;
        uint160 sqrtPriceLimit = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
            params.sqrtPriceOld, params.usableLiquidity, amountInLessFee, true
        );
        sqrtPriceNew = uint160(bound(sqrtPriceNew, sqrtPriceLimit, params.sqrtPriceOld));

        // And: amountOut is at most the largest amountOut that reaches sqrtPriceNew.
        amountOut = bound(
            amountOut,
            0,
            SqrtPriceMath.getAmount1Delta(sqrtPriceNew, params.sqrtPriceOld, params.usableLiquidity, false)
        );

        // When: Calling _capAmount1Out().
        uint256 amountOutCapped = optimizationMath.capAmount1Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioUpper,
            sqrtPriceNew,
            params.amount0,
            amountOut
        );

        // Then: The amountOut is returned unchanged.
        assertEq(amountOutCapped, amountOut);
    }

    function testFuzz_Success_capAmount1Out_Capped(SwapParams memory params, uint160 sqrtPriceNew, uint256 amountOut)
        public
        view
    {
        // Given: A position in range, and a balance of token0 whose net amountIn times sqrtPriceOld fits 256 bits.
        givenValidSwapParams(params, true);
        params.amount0 = bound(params.amount0, 1, type(uint256).max / params.sqrtPriceOld);

        // And: sqrtPriceNew lies below the pool's price for the net amountIn of amount0 − 1, so costs at least amount0.
        uint256 amountInLessFee = (params.amount0 - 1) * (1e6 - params.fee) / 1e6;
        uint160 sqrtPriceLimit = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
            params.sqrtPriceOld, params.usableLiquidity, amountInLessFee, true
        );
        vm.assume(sqrtPriceLimit > TickMath.MIN_SQRT_PRICE);
        sqrtPriceNew = uint160(bound(sqrtPriceNew, TickMath.MIN_SQRT_PRICE, sqrtPriceLimit - 1));

        // When: Calling _capAmount1Out().
        uint256 amountOutCapped = optimizationMath.capAmount1Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioUpper,
            sqrtPriceNew,
            params.amount0,
            amountOut
        );

        // Then: The amountOut is capped at the largest amountOut that reaches that price.
        uint256 amountOutLimit =
            SqrtPriceMath.getAmount1Delta(sqrtPriceLimit, params.sqrtPriceOld, params.usableLiquidity, false);
        assertEq(amountOutCapped, FixedPointMathLib.min(amountOut, amountOutLimit));

        // And: The pool's swap for the capped amountOut leaves at least one wei of token0.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOutCapped);
        assertLt(amountIn, params.amount0);
    }

    function testFuzz_Success_capAmount1Out_CappedAtUpperTick(
        SwapParams memory params,
        uint160 sqrtPriceNew,
        uint256 amountOut
    ) public view {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: A balance of token0 whose net amountIn, less one wei, does not reach the upper tick.
        (uint256 amountInToBound,) = getSwapToBound(params);
        params.amount0 = bound(params.amount0, 1, amountInToBound);

        // And: sqrtPriceNew lies below the pool's price for the net amountIn of amount0 − 1.
        uint160 sqrtPriceLimit = SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp(
            params.sqrtPriceOld, params.usableLiquidity, (params.amount0 - 1) * (1e6 - params.fee) / 1e6, true
        );
        vm.assume(sqrtPriceLimit > TickMath.MIN_SQRT_PRICE);
        sqrtPriceNew = uint160(bound(sqrtPriceNew, TickMath.MIN_SQRT_PRICE, sqrtPriceLimit - 1));

        // When: Calling _capAmount1Out().
        uint256 amountOutCapped = optimizationMath.capAmount1Out(
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioUpper,
            sqrtPriceNew,
            params.amount0,
            amountOut
        );

        // Then: The amountOut is capped at the amountOut of the swap to the upper tick, not before it.
        uint256 amountOutLimit =
            SqrtPriceMath.getAmount1Delta(params.sqrtRatioUpper, params.sqrtPriceOld, params.usableLiquidity, false);
        assertEq(amountOutCapped, FixedPointMathLib.min(amountOut, amountOutLimit));
    }
}
