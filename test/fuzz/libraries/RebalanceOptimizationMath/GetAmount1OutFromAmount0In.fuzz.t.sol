/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_getAmount1OutFromAmount0In" of contract "RebalanceOptimizationMath".
 */
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
    function testFuzz_Success_getAmount1OutFromAmount0In(
        uint256 fee,
        uint128 usableLiquidity,
        uint160 sqrtPriceOld,
        uint256 amount0
    ) public {
        // Given: fee is smaller than 1e6 (invariant).
        fee = bound(fee, 0, 1e6);

        // And: sqrtPriceOld is within boundaries and smaller than type(uint128).max.
        sqrtPriceOld = uint160(bound(sqrtPriceOld, TickMath.MIN_SQRT_PRICE, TickMath.MIN_SQRT_PRICE));

        // And: amountOut without slippage would not overflow.
        amount0 =
            bound(amount0, 0, type(uint256).max / FixedPoint96.Q96 * sqrtPriceOld / FixedPoint96.Q96 * sqrtPriceOld);

        // When: calling _getAmount1OutFromAmount0In().
        // Then: it does not revert.
        uint256 amountOut = optimizationMath.getAmount1OutFromAmount0In(fee, usableLiquidity, sqrtPriceOld, amount0);

        // And: amountOut is always smaller or equal than result without slippage.
        uint256 amountOutWithoutSlippage = FullMath.mulDiv(amount0, sqrtPriceOld, FixedPoint96.Q96);
        amountOutWithoutSlippage = FullMath.mulDiv(amountOutWithoutSlippage, sqrtPriceOld, FixedPoint96.Q96);
        assertLe(amountOut, amountOutWithoutSlippage);
    }
}
