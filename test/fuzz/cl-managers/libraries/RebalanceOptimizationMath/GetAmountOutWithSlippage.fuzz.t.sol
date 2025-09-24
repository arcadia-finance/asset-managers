/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CLMathExtension } from "../../../../utils/extensions/CLMathExtension.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { IQuoterV2 } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IQuoterV2.sol";
import { IUniswapV3PoolExtension } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { QuoterV2Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/QuoterV2Fixture.f.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { RebalanceOptimizationMath_Fuzz_Test } from "./_RebalanceOptimizationMath.fuzz.t.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV3Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_getAmountOutWithSlippage" of contract "RebalanceOptimizationMath".
 */
contract GetAmountOutWithSlippage_SwapMath_Fuzz_Test is
    RebalanceOptimizationMath_Fuzz_Test,
    UniswapV3Fixture,
    QuoterV2Fixture
{
    using stdStorage for StdStorage;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant INITIATOR_FEE = 0.01 * 1e18;
    uint24 internal constant POOL_FEE = 100;
    /// forge-lint: disable-next-line(mixed-case-variable)
    uint128 internal MAX_LIQUIDITY = UniswapHelpers.maxLiquidity(1);

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    CLMathExtension internal cLMath;
    ERC20Mock internal token0;
    ERC20Mock internal token1;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalanceOptimizationMath_Fuzz_Test, UniswapV3Fixture) {
        RebalanceOptimizationMath_Fuzz_Test.setUp();

        UniswapV3Fixture.setUp();
        // nonfungiblePositionManager contract addresses is stored as constant in Rebalancer.
        vm.etch(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1, address(nonfungiblePositionManager).code);

        QuoterV2Fixture.deployQuoterV2(address(uniswapV3Factory), address(weth9));

        cLMath = new CLMathExtension();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getAmountOutWithSlippage(
        uint128 usableLiquidity,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0,
        uint128 amount1,
        uint160 sqrtPriceOld
    ) public {
        // Given: Prices are within reasonable boundaries.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
        tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));

        bool zeroToOne;
        uint256 amountIn;
        uint256 amountOut;
        {
            uint160 sqrtRatioLower = TickMath.getSqrtPriceAtTick(tickLower);
            uint160 sqrtRatioUpper = TickMath.getSqrtPriceAtTick(tickUpper);
            sqrtPriceOld = uint160(bound(sqrtPriceOld, sqrtRatioLower + 1, sqrtRatioUpper - 1));

            // And: Spot value of the tokens is smaller than type(uint120).max for values denominated in both assets.
            amount0 = uint128(
                bound(amount0, 0, type(uint120).max / FixedPoint96.Q96 * sqrtPriceOld / FixedPoint96.Q96 * sqrtPriceOld)
            );
            if (sqrtPriceOld > FixedPoint96.Q96) {
                amount1 = uint128(
                    bound(
                        amount1,
                        0,
                        type(uint120).max / sqrtPriceOld * FixedPoint96.Q96 / sqrtPriceOld * FixedPoint96.Q96
                    )
                );
            }

            // And: total value in token1 is not close to zero.
            vm.assume(amount1 + cLMath.getSpotValue(sqrtPriceOld, true, amount0) > 1e6);

            // And: we start from an estimation based on the slippage free swap.
            (zeroToOne, amountIn, amountOut) = cLMath.getSwapParams(
                sqrtPriceOld, sqrtRatioLower, sqrtRatioUpper, amount0, amount1, INITIATOR_FEE + uint256(POOL_FEE) * 1e12
            );

            // Subtract the initiator fee from amountIn.
            amountIn -= amountIn * INITIATOR_FEE / 1e18;
            zeroToOne
                ? amount0 -= uint128(amountIn * INITIATOR_FEE / 1e18)
                : amount1 -= uint128(amountIn * INITIATOR_FEE / 1e18);

            // And: either amountIn or amountOut is not zero.
            vm.assume(amountIn > 0 && amountOut > 0);

            // And: Liquidity0 does not overflow (smaller than type(uint120).max).
            {
                uint256 balance0 = zeroToOne ? amount0 - amountIn : amount0 + amountOut;
                uint256 balance1 = zeroToOne ? amount1 + amountOut : amount1 - amountIn;
                uint256 liquidity0;
                {
                    uint256 intermediate = FullMath.mulDiv(sqrtPriceOld, sqrtRatioUpper, FixedPoint96.Q96);
                    if (intermediate > sqrtRatioUpper - sqrtPriceOld) {
                        vm.assume(
                            balance0 < FullMath.mulDiv(type(uint256).max, sqrtRatioUpper - sqrtPriceOld, intermediate)
                        );
                    }
                    liquidity0 = FullMath.mulDiv(balance0, intermediate, sqrtRatioUpper - sqrtPriceOld);
                }
                vm.assume(liquidity0 < type(uint128).max);

                // And: Liquidity1 does not overflow (smaller than type(uint120).max).
                uint256 liquidity1 = FullMath.mulDiv(balance1, FixedPoint96.Q96, sqrtPriceOld - sqrtRatioLower);
                vm.assume(liquidity1 < type(uint128).max);

                // And: usableLiquidity is at least double as big as liquidity of position.
                vm.assume(2 * (liquidity0 < liquidity1 ? liquidity0 : liquidity1) < MAX_LIQUIDITY);
                usableLiquidity = uint128(
                    bound(usableLiquidity, 2 * (liquidity0 < liquidity1 ? liquidity0 : liquidity1), MAX_LIQUIDITY)
                );
            }
        }

        // And: No over-underflows in price due to excess slippage (usableLiquidity too small).
        if (zeroToOne) {
            vm.assume(amountOut * FixedPoint96.Q96 / sqrtPriceOld <= MAX_LIQUIDITY);
            usableLiquidity =
                uint128(bound(usableLiquidity, amountOut * FixedPoint96.Q96 / sqrtPriceOld, MAX_LIQUIDITY));
            vm.assume(sqrtPriceOld > FullMath.mulDivRoundingUp(amountOut, FixedPoint96.Q96, usableLiquidity));
        } else {
            uint256 product = uint256(amountOut) * sqrtPriceOld;
            usableLiquidity = uint128(bound(usableLiquidity, product / FixedPoint96.Q96, MAX_LIQUIDITY));
            uint256 numerator1 = uint256(usableLiquidity) << FixedPoint96.RESOLUTION;
            uint256 denominator = numerator1 - product;
            vm.assume(FullMath.mulDivRoundingUp(numerator1, sqrtPriceOld, denominator) <= type(uint160).max);
        }

        // Mint usable liquidity to use the quoter.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        {
            IUniswapV3PoolExtension pool =
                createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceOld, 300);
            addLiquidityUniV3(
                pool, usableLiquidity, users.liquidityProvider, TickMath.MIN_TICK, TickMath.MAX_TICK, false
            );
            stdstore.target(address(pool)).sig(pool.liquidity.selector).checked_write(usableLiquidity);
            deal(address(token0), address(pool), type(uint160).max, true);
            deal(address(token1), address(pool), type(uint160).max, true);
        }

        // Exclude edge case where sqrtPriceAfter is out of range.
        {
            uint160 sqrtPriceNew = optimizationMath.approximateSqrtPriceNew(
                zeroToOne, POOL_FEE, usableLiquidity, sqrtPriceOld, amountIn, amountOut
            );
            vm.assume(
                TickMath.getSqrtPriceAtTick(tickLower) < sqrtPriceNew * 99_999 / 100_000
                    && sqrtPriceNew * 100_001 / 100_000 < TickMath.getSqrtPriceAtTick(tickUpper)
            );
        }

        // When: Calling _getAmountOutWithSlippage().
        // Then: It does not revert.
        uint256 amountOutWithSlippage = optimizationMath.getAmountOutWithSlippage(
            zeroToOne,
            POOL_FEE,
            usableLiquidity,
            sqrtPriceOld,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1,
            amountIn,
            amountOut
        );

        // And:Liquidity added with swap params calculated with slippage,
        // is bigger than or equal to the liquidity added with swap params calculated without slippage.
        (uint256 liquidityWithSlippage, uint256 amountInWithSlippage) = getLiquidityAfterSwap(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1,
            zeroToOne,
            amountOutWithSlippage,
            false
        );

        (uint256 liquidityWithoutSlippage, uint256 amountInWithoutSlippage) = getLiquidityAfterSwap(
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1,
            zeroToOne,
            amountOut,
            true
        );

        // Rounding errors are relatively too big with very low amountIns.
        vm.assume(amountInWithSlippage > 1e5);

        // If amount in's are equal, liquidity will be almost exactly equal,
        // but it can be that "without slippage" is bigger in this specific case due to rounding errors.
        if (
            amountInWithSlippage == amountInWithoutSlippage || amountInWithSlippage == amountInWithoutSlippage + 1
                || amountInWithSlippage + 1 == amountInWithoutSlippage
        ) {
            assertApproxEqRel(amountInWithSlippage, amountInWithoutSlippage, 0.005 * 1e18);
        } else {
            assertGe(liquidityWithSlippage, liquidityWithoutSlippage);
        }
    }

    function getLiquidityAfterSwap(
        uint160 sqrtRatioLower,
        uint160 sqrtRatioUpper,
        uint128 amount0,
        uint128 amount1,
        bool zeroToOne,
        uint256 amountOut,
        bool canRevertOnQuote
    ) internal returns (uint256 liquidity, uint256 amountIn) {
        uint160 sqrtPriceAfter;
        try quoter.quoteExactOutputSingle(
            IQuoterV2.QuoteExactOutputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountOut: amountOut,
                fee: POOL_FEE,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 amountIn_, uint160 sqrtPriceAfter_, uint32, uint256) {
            amountIn = amountIn_;
            sqrtPriceAfter = sqrtPriceAfter_;
        } catch {
            // Swaps with amountOutWithoutSlippage can revert on the swap (it is due to slippage),
            // but swaps with amountOutWithSlippage should not revert.
            if (canRevertOnQuote) vm.assume(false);
            else revert();
        }

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceAfter,
            sqrtRatioLower,
            sqrtRatioUpper,
            zeroToOne ? (amount0 > amountIn ? amount0 - amountIn : 0) : amount0 + amountOut,
            zeroToOne ? amount1 + amountOut : (amount1 > amountIn ? amount1 - amountIn : 0)
        );
    }
}
