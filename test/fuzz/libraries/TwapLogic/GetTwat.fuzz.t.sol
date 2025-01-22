/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import {
    ExactOutputSingleParams, ISwapRouter02
} from "../../../../src/compounders/uniswap-v3/interfaces/ISwapRouter02.sol";
import { TwapLogic_Fuzz_Test } from "./_TwapLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_transfer" of contract "TwapLogic".
 */
contract GetTwat_TwapLogic_Fuzz_Test is TwapLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(TwapLogic_Fuzz_Test) {
        TwapLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getTwat(
        uint256 timePassed,
        int24 tickLower,
        int24 tickUpper,
        uint96 amount0Initial,
        uint96 amountOut0,
        uint96 amountOut1
    ) public {
        // Limit timePassed between the two swaps to 300s (the TWAT duration).
        timePassed = bound(timePassed, 0, 300);

        // Check that ticks are within allowed ranges.
        vm.assume(tickLower < tickUpper);
        vm.assume(isWithinAllowedRange(tickLower));
        vm.assume(isWithinAllowedRange(tickUpper));

        // Check that amounts are within allowed ranges.
        // Avoid error "SPL" when amountOut1 is very small and amountOut0~amount0Initial.
        amount0Initial = uint96(bound(amount0Initial, 2000, type(uint88).max));
        amountOut1 = uint96(bound(amountOut1, 10, amount0Initial - 1100));
        amountOut0 = uint96(bound(amountOut0, 10, amount0Initial - amountOut1 - 1000));

        // Create a pool with the minimum initial price (4_295_128_739) and cardinality 300.
        pool = createPoolUniV3(address(token0), address(token1), POOL_FEE, 4_295_128_739, 300);

        // Provide liquidity only in token0.
        vm.assume(isBelowMaxLiquidityPerTick(tickLower, tickUpper, amount0Initial, 0, pool));
        addLiquidityUniV3(pool, amount0Initial, 0, users.liquidityProvider, tickLower, tickUpper, false);

        // Do a first swap.
        deal(address(token1), users.swapper, type(uint256).max);
        vm.startPrank(users.swapper);
        token1.approve(address(swapRouter), type(uint256).max);
        ISwapRouter02(address(swapRouter)).exactOutputSingle(
            ExactOutputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: POOL_FEE,
                recipient: users.swapper,
                amountOut: amountOut0,
                amountInMaximum: type(uint160).max,
                sqrtPriceLimitX96: 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341
            })
        );
        vm.stopPrank();

        // Cache the current tick after the first swap.
        (, int24 tick0,,,,,) = pool.slot0();

        // Do second swap after timePassed seconds.
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + timePassed);
        vm.startPrank(users.swapper);
        token1.approve(address(swapRouter), type(uint256).max);
        ISwapRouter02(address(swapRouter)).exactOutputSingle(
            ExactOutputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: POOL_FEE,
                recipient: users.swapper,
                amountOut: amountOut1,
                amountInMaximum: type(uint160).max,
                sqrtPriceLimitX96: 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_341
            })
        );
        vm.stopPrank();

        // Cache the current tick after the second swap.
        (, int24 tick1,,,,,) = pool.slot0();

        // Calculate the TWAT.
        vm.warp(timestamp + 300);
        int256 expectedTickTwap =
            (int256(tick0) * int256(timePassed) + int256(tick1) * int256((300 - timePassed))) / 300;

        // Compare with the actual TWAT.
        int256 actualTickTwap = twapLogic.getTwat(address(pool));
        assertEq(actualTickTwap, expectedTickTwap);
    }
}
