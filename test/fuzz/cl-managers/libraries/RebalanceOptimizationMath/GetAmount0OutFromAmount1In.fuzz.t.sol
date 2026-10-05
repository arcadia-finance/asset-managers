/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { FixedPoint96 } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmount0OutFromAmount1In" of contract "RebalanceOptimizationMath".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract GetAmount0OutFromAmount1In_SwapMath_Fuzz_Test is RebalanceOptimizationMath_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalanceOptimizationMath_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmount0OutFromAmount1In(SwapParams memory params) public view {
        // Given: A oneToZero swap.
        params.zeroToOne = false;

        // And: fee is smaller than 1e6 (invariant).
        params.fee = bound(params.fee, 0, 1e6 - 1);

        // And: usableLiquidity is not near zero.
        params.usableLiquidity = uint128(bound(params.usableLiquidity, 1e18, type(uint128).max));

        // And: sqrtPriceOld is within boundaries.
        params.sqrtPriceOld = uint160(bound(params.sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MAX_SQRT_PRICE));

        // And: amount1 fits in a uint128.
        params.amount1 = bound(params.amount1, 0, type(uint128).max);

        // And: The new sqrtPrice fits in a uint160.
        uint256 amountInLessFee = params.amount1 * (1e6 - params.fee) / 1e6;
        uint256 quotient =
            (amountInLessFee <= type(uint160).max
                ? (amountInLessFee << FixedPoint96.RESOLUTION) / params.usableLiquidity
                : FullMath.mulDiv(amountInLessFee, FixedPoint96.Q96, params.usableLiquidity));
        vm.assume(params.sqrtPriceOld + quotient < type(uint160).max);

        // When: calling _getAmount0OutFromAmount1In().
        // Then: it does not revert.
        uint256 amountOut = optimizationMath.getAmount0OutFromAmount1In(
            params.fee, params.usableLiquidity, params.sqrtPriceOld, params.amount1
        );

        // And: amountOut is the amountOut of the pool for amount1 less the fee, rounded down.
        assertEq(amountOut, getAmountOutForAmountIn(params, params.amount1));

        // And: amountOut is always smaller or equal than result without slippage, amount1 * 2^192 / sqrtPriceOld² rounded down.
        uint256 partialQuotient = FullMath.mulDiv(params.amount1, 1 << 96, params.sqrtPriceOld);
        uint256 carry = (mulmod(params.amount1, 1 << 96, params.sqrtPriceOld) << 96) / params.sqrtPriceOld;
        carry += mulmod(partialQuotient, 1 << 96, params.sqrtPriceOld);
        uint256 amountOutWithoutSlippage =
            FullMath.mulDiv(partialQuotient, 1 << 96, params.sqrtPriceOld) + carry / params.sqrtPriceOld;
        assertLe(amountOut, amountOutWithoutSlippage);

        // And: The amountIn of the pool for amountOut is smaller or equal than amount1.
        (, uint256 amountIn) = getAmountInForAmountOut(params, amountOut);
        assertLe(amountIn, params.amount1);
    }
}
