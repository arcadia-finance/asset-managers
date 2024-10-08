/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { SwapLogic_Fuzz_Test } from "./_SwapLogic.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../src/rebalancers/libraries/uniswap-v3/SqrtPriceMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_swapViaPool" of contract "SwapLogic".
 */
contract SwapViaPool_SwapLogic_Fuzz_Test is SwapLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(SwapLogic_Fuzz_Test) {
        SwapLogic_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_oneToZero_UniswapV3(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;
        position.pool = address(poolUniswap);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolUniswap)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolUniswap)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolUniswap.liquidity(), amountOut, true
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount0Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolUniswap.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is still balanced after the swap.
        position.lowerBoundSqrtPriceX96 =
            uint160(bound(position.lowerBoundSqrtPriceX96, BOUND_SQRT_PRICE_LOWER, sqrtPriceNew - 10));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(address(nonfungiblePositionManager), position, true, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance1_ - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balance0_, 0.01 * 1e18);

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_UniswapV3(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;
        position.pool = address(poolUniswap);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolUniswap)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolUniswap)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolUniswap.liquidity(), amountOut, false
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount1Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolUniswap.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is still balanced after the swap.
        position.upperBoundSqrtPriceX96 =
            uint160(bound(position.upperBoundSqrtPriceX96, sqrtPriceNew + 10, BOUND_SQRT_PRICE_UPPER));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(address(nonfungiblePositionManager), position, false, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance0_ - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balance1_, 0.01 * 1e18);

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_oneToZero_Slipstream(
        address positionManager,
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: positionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(nonfungiblePositionManager));

        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.tickSpacing = TICK_SPACING;
        position.pool = address(poolCl);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolCl)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolCl)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolCl.liquidity(), amountOut, true
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount0Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolCl.liquidity(), true);
        uint256 amountIn = amountInLessFee * (1e6 - poolCl.fee()) / 1e6;
        vm.assume(amountIn > 10);

        // And: Contract has balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is still balanced after the swap.
        position.lowerBoundSqrtPriceX96 =
            uint160(bound(position.lowerBoundSqrtPriceX96, BOUND_SQRT_PRICE_LOWER, sqrtPriceNew - 10));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(positionManager, position, true, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance1_ - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balance0_, 0.01 * 1e18);

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_Slipstream(
        address positionManager,
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: positionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(nonfungiblePositionManager));

        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.tickSpacing = TICK_SPACING;
        position.pool = address(poolCl);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolCl)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolCl)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolCl.liquidity(), amountOut, false
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount1Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolCl.liquidity(), true);
        uint256 amountIn = amountInLessFee * (1e6 - poolCl.fee()) / 1e6;
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is still balanced after the swap.
        position.upperBoundSqrtPriceX96 =
            uint160(bound(position.upperBoundSqrtPriceX96, sqrtPriceNew + 10, BOUND_SQRT_PRICE_UPPER));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(positionManager, position, false, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance0_ - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balance1_, 0.01 * 1e18);

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_oneToZero_Unbalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;
        position.pool = address(poolUniswap);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolUniswap)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolUniswap)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolUniswap.liquidity(), amountOut, true
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount0Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolUniswap.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(position.sqrtPriceX96 - sqrtPriceNew > 1);
        position.lowerBoundSqrtPriceX96 =
            uint160(bound(position.lowerBoundSqrtPriceX96, sqrtPriceNew + 1, uint160(position.sqrtPriceX96) - 1));

        // When: Calling swapViaPool.
        (,, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(address(nonfungiblePositionManager), position, true, amountOut, balance0, balance1);

        // Then: The sqrtPriceX96 equals the lower bound.
        assertEq(position_.sqrtPriceX96, position.lowerBoundSqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_Unbalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;
        position.pool = address(poolUniswap);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolUniswap)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolUniswap)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), poolUniswap.liquidity(), amountOut, false
        );
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount1Delta(sqrtPriceNew, uint160(position.sqrtPriceX96), poolUniswap.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(sqrtPriceNew - position.sqrtPriceX96 > 1);
        position.upperBoundSqrtPriceX96 =
            uint160(bound(position.upperBoundSqrtPriceX96, uint160(position.sqrtPriceX96) + 1, sqrtPriceNew - 1));

        // When: Calling swapViaPool.
        (,, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaPool(address(nonfungiblePositionManager), position, false, amountOut, balance0, balance1);

        // Then: The sqrtPriceX96 equals the upper bound.
        assertEq(position_.sqrtPriceX96, position.upperBoundSqrtPriceX96);
    }
}
