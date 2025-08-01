/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";
import { SqrtPriceMath } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_swapViaPool" of contract "UniswapV4".
 */
contract SwapViaPool_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_NotNative_ZeroToOne_Balanced(
        uint128 liquidityPool,
        PositionState memory position,
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

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, true, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_swapViaPool_NotNative_OneToZero_Balanced(
        uint128 liquidityPool,
        PositionState memory position,
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

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, false, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_swapViaPool_IsNative_ZeroToOne_Balanced(
        uint128 liquidityPool,
        PositionState memory position,
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

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), amountOut, true
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount0Delta(
            sqrtPriceNew, uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(base), balance0);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, true, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], address(base).balance);
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_swapViaPool_IsNative_OneToZero_Balanced(
        uint128 liquidityPool,
        PositionState memory position,
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

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), amountOut, false
        );
        uint256 amountInLessFee = SqrtPriceMath.getAmount1Delta(
            sqrtPriceNew, uint160(position.sqrtPrice), stateView.getLiquidity(poolKey.toId()), true
        );
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - POOL_FEE);
        vm.assume(amountIn > 10);

        // And: Contract has sufficient balances.
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(base), balance0);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, false, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], address(base).balance);
        assertEq(balances[1], token1.balanceOf(address(base)));
    }
}
