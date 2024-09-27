/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/uniswap-v3/LiquidityAmounts.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/PricingLogic.sol";
import { SwapMathExtension } from "../../../utils/extensions/SwapMathExtension.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "SwapMath" fuzz tests.
 */
abstract contract SwapMath_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 MAX_INITIATOR_FEE = 0.01 * 1e18;

    uint256 BOUND_SQRT_PRICE_LOWER = TickMath.getSqrtRatioAtTick(-TickMath.getTickAtSqrtRatio(type(uint128).max));
    uint256 BOUND_SQRT_PRICE_UPPER = type(uint128).max;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SwapMathExtension internal swapMath;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        swapMath = new SwapMathExtension();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function getLiquidityAmounts(
        uint160 sqrtPrice,
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 amount0_, uint256 amount1_) {
        uint128 liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, amount0, amount1);
        (amount0_, amount1_) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPrice, sqrtRatioLower, sqrtRatioUpper, liquidity);
    }
}
