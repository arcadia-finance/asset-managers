/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/uniswap-v3/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "swapViaPool" of contract "RebalancerUniswapV4".
 */
contract SwapViaPool_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_oneToZero(
        uint128 liquidityPool,
        RebalancerUniswapV4.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        position.lowerBoundSqrtPriceX96 =
            uint160(bound(position.lowerBoundSqrtPriceX96, BOUND_SQRT_PRICE_LOWER, sqrtPriceNew - 10));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, RebalancerUniswapV4.PositionState memory position_) =
            rebalancer.swapViaPool(v4PoolKey, position, true, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance1_ - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balance0_, 0.01 * 1e18);
        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne(
        uint128 liquidityPool,
        RebalancerUniswapV4.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        position.upperBoundSqrtPriceX96 =
            uint160(bound(position.upperBoundSqrtPriceX96, sqrtPriceNew + 10, BOUND_SQRT_PRICE_UPPER));

        // When: Calling swapViaPool.
        (uint256 balance0_, uint256 balance1_, RebalancerUniswapV4.PositionState memory position_) =
            rebalancer.swapViaPool(v4PoolKey, position, false, amountOut, balance0, balance1);

        // Then: The correct balances are returned.
        assertEq(amountOut, balance0_ - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balance1_, 0.01 * 1e18);
        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_oneToZero_Unbalanced(
        uint128 liquidityPool,
        RebalancerUniswapV4.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(position.sqrtPriceX96 - sqrtPriceNew > 1);
        position.lowerBoundSqrtPriceX96 =
            uint160(bound(position.lowerBoundSqrtPriceX96, sqrtPriceNew + 1, uint160(position.sqrtPriceX96) - 1));

        // When: Calling swapViaPool.
        (,, RebalancerUniswapV4.PositionState memory position_) =
            rebalancer.swapViaPool(v4PoolKey, position, true, amountOut, balance0, balance1);

        // Then: The sqrtPriceX96 equals the lower bound.
        assertEq(position_.sqrtPriceX96, position.lowerBoundSqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_Unbalanced(
        uint128 liquidityPool,
        RebalancerUniswapV4.PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.fee = POOL_FEE;

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(v4PoolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(sqrtPriceNew - position.sqrtPriceX96 > 1);
        position.upperBoundSqrtPriceX96 =
            uint160(bound(position.upperBoundSqrtPriceX96, uint160(position.sqrtPriceX96) + 1, sqrtPriceNew - 1));

        // When: Calling swapViaPool.
        (,, RebalancerUniswapV4.PositionState memory position_) =
            rebalancer.swapViaPool(v4PoolKey, position, false, amountOut, balance0, balance1);

        // Then: The sqrtPriceX96 equals the upper bound.
        assertEq(position_.sqrtPriceX96, position.upperBoundSqrtPriceX96);
    }
}
