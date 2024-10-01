/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/uniswap-v3/LiquidityAmounts.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/PricingLogic.sol";
import { RebalanceOptimizationMathExtension } from "../../../utils/extensions/RebalanceOptimizationMathExtension.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all "RebalanceOptimizationMath" fuzz tests.
 */
abstract contract RebalanceOptimizationMath_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_INITIATOR_FEE = 0.01 * 1e18;

    uint160 internal BOUND_SQRT_PRICE_UPPER = type(uint120).max;
    int24 internal BOUND_TICK_UPPER = TickMath.getTickAtSqrtRatio(BOUND_SQRT_PRICE_UPPER);
    int24 internal BOUND_TICK_LOWER = -BOUND_TICK_UPPER;
    uint160 internal BOUND_SQRT_PRICE_LOWER = TickMath.getSqrtRatioAtTick(BOUND_TICK_LOWER);

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

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