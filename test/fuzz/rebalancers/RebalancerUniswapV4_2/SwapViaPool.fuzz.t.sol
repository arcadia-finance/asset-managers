/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer, RebalanceParams } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_swapViaPool" of contract "RebalancerUniswapV4".
 */
contract SwapViaPool_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_NotNative_ZeroToOne_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = true;

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        cache.lowerBoundSqrtPriceX96 =
            uint160(bound(cache.lowerBoundSqrtPriceX96, BOUND_SQRT_PRICE_LOWER, sqrtPriceNew - 10));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_NotNative_ZeroToOne_Unbalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = true;

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        vm.assume(position.sqrtPriceX96 - sqrtPriceNew > 1);
        cache.lowerBoundSqrtPriceX96 =
            uint160(bound(cache.lowerBoundSqrtPriceX96, sqrtPriceNew + 1, uint160(position.sqrtPriceX96) - 1));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // Then: The sqrtPriceX96 equals the lower bound.
        assertEq(position_.sqrtPriceX96, cache.lowerBoundSqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_NotNative_OneToZero_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token0.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = false;

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        cache.upperBoundSqrtPriceX96 =
            uint160(bound(cache.upperBoundSqrtPriceX96, sqrtPriceNew + 10, BOUND_SQRT_PRICE_UPPER));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_NotNative_OneToZero_UnBalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token0.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token0.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = false;

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(sqrtPriceNew - position.sqrtPriceX96 > 1);
        cache.upperBoundSqrtPriceX96 =
            uint160(bound(cache.upperBoundSqrtPriceX96, uint160(position.sqrtPriceX96) + 1, sqrtPriceNew - 1));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // Then: The sqrtPriceX96 equals the upper bound.
        assertEq(position_.sqrtPriceX96, cache.upperBoundSqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_IsNative_ZeroToOne_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = true;

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        cache.lowerBoundSqrtPriceX96 =
            uint160(bound(cache.lowerBoundSqrtPriceX96, BOUND_SQRT_PRICE_LOWER, sqrtPriceNew - 10));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_IsNative_ZeroToOne_Unbalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(token1.balanceOf(address(poolManager)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolManager)) / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = true;

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        vm.assume(position.sqrtPriceX96 - sqrtPriceNew > 1);
        cache.lowerBoundSqrtPriceX96 =
            uint160(bound(cache.lowerBoundSqrtPriceX96, sqrtPriceNew + 1, uint160(position.sqrtPriceX96) - 1));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // Then: The sqrtPriceX96 equals the lower bound.
        assertEq(position_.sqrtPriceX96, cache.lowerBoundSqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_IsNative_OneToZero_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(address(poolManager).balance > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, address(poolManager).balance / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = false;

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is still balanced after the swap.
        cache.upperBoundSqrtPriceX96 =
            uint160(bound(cache.upperBoundSqrtPriceX96, sqrtPriceNew + 10, BOUND_SQRT_PRICE_UPPER));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPriceX96 remains equal.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaPool_IsNative_OneToZero_UnBalanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Pool has sufficient tokenOut liquidity.
        vm.assume(address(poolManager).balance > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, address(poolManager).balance / 10));

        // Get the new sqrtPriceX96 and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPriceX96), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Swap is zeroToOne.
        rebalanceParams.zeroToOne = false;

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: The pool is unbalanced after the swap.
        vm.assume(sqrtPriceNew - position.sqrtPriceX96 > 1);
        cache.upperBoundSqrtPriceX96 =
            uint160(bound(cache.upperBoundSqrtPriceX96, uint160(position.sqrtPriceX96) + 1, sqrtPriceNew - 1));

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams, cache, amountOut);

        // Then: The correct balances are returned.
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // Then: The sqrtPriceX96 equals the upper bound.
        assertEq(position_.sqrtPriceX96, cache.upperBoundSqrtPriceX96);
    }
}
