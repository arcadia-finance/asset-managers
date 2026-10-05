/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getAmountOutWithSlippage" of contract "RebalanceOptimizationMath".
 */
contract GetAmountOutWithSlippage_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmountOutWithSlippage_ZeroToOne(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld above the upper tick.
        givenValidSwapParamsOutOfRange(params, true);

        // And: amount0 is smaller than the amountIn to move the price to the upper tick.
        (uint256 amountInToBound,) = getSwapToBound(params);
        params.amount0 = bound(params.amount0, 0, amountInToBound - 1);

        // When: Calling _getAmountOutWithSlippage().
        uint256 amountOut = optimizationMath.getAmountOutWithSlippage(
            params.zeroToOne,
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );

        // Then: amountOut is the amountOut of the pool for a swap of the full amount0.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount0));
    }

    function testFuzz_Success_getAmountOutWithSlippage_OneToZero(SwapParams memory params) public view {
        // Given: A position with sqrtPriceOld below the lower tick.
        givenValidSwapParamsOutOfRange(params, false);

        // And: amount1 is smaller than the amountIn to move the price to the lower tick.
        (uint256 amountInToBound,) = getSwapToBound(params);
        params.amount1 = bound(params.amount1, 0, amountInToBound - 1);

        // When: Calling _getAmountOutWithSlippage().
        uint256 amountOut = optimizationMath.getAmountOutWithSlippage(
            params.zeroToOne,
            params.fee,
            params.usableLiquidity,
            params.sqrtPriceOld,
            params.sqrtRatioLower,
            params.sqrtRatioUpper,
            params.amount0,
            params.amount1
        );

        // Then: amountOut is the amountOut of the pool for a swap of the full amount1.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount1));
    }
}
