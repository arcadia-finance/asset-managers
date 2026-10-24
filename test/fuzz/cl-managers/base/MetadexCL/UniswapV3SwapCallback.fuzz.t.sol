/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { Slipstream } from "../../../../../src/cl-managers/base/Slipstream.sol";

/**
 * @notice Fuzz tests for the function "uniswapV3SwapCallback" of contract "Slipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract UniswapV3SwapCallback_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();

        initMetadexCL();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_uniswapV3SwapCallback_NonPool(
        uint128 balance0,
        uint128 balance1,
        int128 amount0Delta,
        int128 amount1Delta,
        address caller
    ) public {
        // Given: Caller is not the pool.
        vm.assume(caller != address(poolCl));

        // And: Base has balances.
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Caller calls uniswapV3SwapCallback.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(caller);
        vm.expectRevert(Slipstream.OnlyPool.selector);
        // Then: It reverts.
        base.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);
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

        // And: Base has sufficient balances.
        balance0 = uint128(bound(balance0, uint128(amount0Delta), type(uint128).max));
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: The Metadex CL Pool calls uniswapV3SwapCallback.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(address(poolCl));
        base.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);

        // Then: The correct balances are returned.
        assertEq(balance0 - uint128(amount0Delta), token0.balanceOf(address(base)));
        assertEq(balance1, token1.balanceOf(address(base)));
    }

    function testFuzz_Success_uniswapV3SwapCallback_OneToZero(
        uint128 balance0,
        uint128 balance1,
        int128 amount0Delta,
        int128 amount1Delta
    ) public {
        // Given: OneToZero swap.
        amount0Delta = int128(bound(amount0Delta, type(int128).min, 0));
        amount1Delta = int128(bound(amount1Delta, 0, type(int128).max));

        // And: Base has sufficient balances.
        balance1 = uint128(bound(balance1, uint128(amount1Delta), type(uint128).max));
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: The Metadex CL Pool calls uniswapV3SwapCallback.
        bytes memory data = abi.encode(address(token0), address(token1), TICK_SPACING);
        vm.prank(address(poolCl));
        base.uniswapV3SwapCallback(amount0Delta, amount1Delta, data);

        // Then: The correct balances are returned.
        assertEq(balance0, token0.balanceOf(address(base)));
        assertEq(balance1 - uint128(amount1Delta), token1.balanceOf(address(base)));
    }
}
