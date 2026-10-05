/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmount1OutFromAmount0In" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmount1OutFromAmount0In_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmount1OutFromAmount0In(SwapParams memory params) public view {
        // Given: A zeroToOne swap.
        params.zeroToOne = true;

        // And: fee is smaller than 1e6 (invariant).
        params.fee = bound(params.fee, 0, 1e6 - 1);

        // And: usableLiquidity is not zero.
        params.usableLiquidity = uint128(bound(params.usableLiquidity, 1, type(uint128).max));

        // And: sqrtPriceOld is within boundaries.
        params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));

        // And: amountOut without slippage would not overflow.
        params.amount0 = bound(params.amount0, 0, type(uint128).max);

        // When: calling _getAmount1OutFromAmount0In().
        // Then: it does not revert.
        uint256 amountOut = optimizationMath.getAmount1OutFromAmount0In(
            params.fee, params.usableLiquidity, params.sqrtPriceOld, params.amount0
        );

        // And: amountOut is the amountOut of the pool for amount0 less the fee, rounded down.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount0));

        // And: amountOut is always smaller or equal than result without slippage, amount0 * sqrtPriceOld² / 2^192 rounded down.
        uint256 partialQuotient = FullMath.mulDiv(params.amount0, params.sqrtPriceOld, 1 << 96);
        uint256 carry = (mulmod(params.amount0, params.sqrtPriceOld, 1 << 96) * params.sqrtPriceOld) >> 96;
        carry += mulmod(partialQuotient, params.sqrtPriceOld, 1 << 96);
        uint256 amountOutWithoutSlippage =
            FullMath.mulDiv(partialQuotient, params.sqrtPriceOld, 1 << 96) + (carry >> 96);
        assertLe(amountOut, amountOutWithoutSlippage);

        // And: The amountIn of the pool for amountOut is smaller or equal than amount0.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(amountIn, params.amount0);
    }
}
