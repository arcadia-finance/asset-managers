/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Slipstream } from "../../../../src/base/Slipstream.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "uniswapV3SwapCallback" of contract "RebalancerSlipstream".
 */
contract UniswapV3SwapCallback_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();

        initSlipstream();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_uniswapV3SwapCallback_NonPool(
        uint128 balance0,
        uint128 balance1,
        int128 amount0Delta,
        int128 amount1Delta,
        address caller
    ) public {
        // Given: Caller is not the pool.
        vm.assume(caller != address(poolCl));

        // And: Rebalancer has sufficient balances.
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // When: The Uniswap Pool calls uniswapV3SwapCallback.
        // Then: It should revert.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(caller);
        vm.expectRevert(Slipstream.OnlyPool.selector);
        rebalancer.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
    }

    function testFuzz_Success_uniswapV3SwapCallback_ZeroToOne(
        uint128 balance0,
        uint128 balance1,
        int128 amount0Delta,
        int128 amount1Delta
    ) public {
        // Given: ZeroToOne swap.
        amount0Delta = int128(bound(amount0Delta, 0, type(int128).max));
        amount1Delta = int128(bound(amount1Delta, type(int128).min, 0));

        // And: Rebalancer has sufficient balances.
        balance0 = uint128(bound(balance0, uint128(amount0Delta), type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // When: The Uniswap Pool calls uniswapV3SwapCallback.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(address(poolCl));
        rebalancer.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);

        // Then: The correct balances are returned.
        assertEq(balance0 - uint128(amount0Delta), token0.balanceOf(address(rebalancer)));
        assertEq(balance1, token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_uniswapV3SwapCallback_OneToZero(
        uint128 balance0,
        uint128 balance1,
        int128 amount0Delta,
        int128 amount1Delta
    ) public {
        // Given: ZeroToOne swap.
        amount0Delta = int128(bound(amount0Delta, type(int128).min, 0));
        amount1Delta = int128(bound(amount1Delta, 0, type(int128).max));

        // Given: Rebalancer has sufficient balances.
        balance1 = uint128(bound(balance1, uint128(amount1Delta), type(uint128).max));
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // When: The Uniswap Pool calls uniswapV3SwapCallback.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(address(poolCl));
        rebalancer.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);

        // Then: The correct balances are returned.
        assertEq(balance0, token0.balanceOf(address(rebalancer)));
        assertEq(balance1 - uint128(amount1Delta), token1.balanceOf(address(rebalancer)));
    }
}
