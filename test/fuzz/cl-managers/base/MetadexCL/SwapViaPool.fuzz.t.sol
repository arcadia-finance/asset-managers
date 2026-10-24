/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { IMockSwapHook } from "../../../../../lib/accounts-v2/test/utils/mocks/Metadex03/interfaces/IMockSwapHook.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_swapViaPool" of contract "Slipstream", on Metadex CL.
 */
contract SwapViaPool_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              CONSTANTS
    /////////////////////////////////////////////////////////////// */

    // The hard cap on hook supplied swap fees, of 1e6.
    uint24 internal constant SWAP_FEE_CEIL = 100_000;

    /* ///////////////////////////////////////////////////////////////
                              VARIABLES
    /////////////////////////////////////////////////////////////// */

    IMockSwapHook internal swapHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();

        swapHook = IMockSwapHook(deployCode("MockSwapHook.sol"));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a balanced pool with a position and returns the amountOut and the pool-fee derived amountIn.
    function setSwapState(uint128 liquidityPool, PositionState memory position, uint64 amountOut)
        internal
        returns (uint256 amountOut_, uint256 amountIn)
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        vm.assume(token1.balanceOf(address(poolCl)) > 1e6);
        amountOut_ = bound(amountOut, 1e5, token1.balanceOf(address(poolCl)) / 10);

        // forge-lint: disable-next-item(unsafe-typecast)
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            uint160(position.sqrtPrice), poolCl.liquidity(), amountOut_, true
        );
        // forge-lint: disable-next-item(unsafe-typecast)
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount0Delta(sqrtPriceNew, uint160(position.sqrtPrice), poolCl.liquidity(), true);
        amountIn = amountInLessFee * 1e6 / (1e6 - poolCl.fee());
        vm.assume(amountIn > 10);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_ZeroToOne_Balanced(
        uint128 liquidityPool,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position and a swappable amount.
        (uint256 amountOut_, uint256 amountIn) = setSwapState(liquidityPool, position, amountOut);

        // And: Base has sufficient balances.
        // forge-lint: disable-next-item(unsafe-typecast)
        balance0 = uint128(bound(balance0, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, true, amountOut_);

        // Then: The correct balances are returned.
        assertEq(amountOut_, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        // And: The sqrtPrice remains equal.
        assertEq(position_.sqrtPrice, position.sqrtPrice);
    }

    function testFuzz_Success_swapViaPool_OneToZero_Balanced(
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
        vm.assume(token0.balanceOf(address(poolCl)) > 1e6);
        uint256 amountOut_ = bound(amountOut, 1e5, token0.balanceOf(address(poolCl)) / 10);

        // forge-lint: disable-next-item(unsafe-typecast)
        // And: The amountIn is derived from the pool fee.
        uint160 sqrtPriceNew = SqrtPriceMath.getNextSqrtPriceFromOutput(
            // forge-lint: disable-next-item(unsafe-typecast)
            uint160(position.sqrtPrice),
            poolCl.liquidity(),
            amountOut_,
            false
        );
        uint256 amountIn = SqrtPriceMath.getAmount1Delta(
                // forge-lint: disable-next-item(unsafe-typecast)
                sqrtPriceNew,
                uint160(position.sqrtPrice),
                poolCl.liquidity(),
                true
            ) * 1e6 / (1e6 - poolCl.fee());
        vm.assume(amountIn > 10);

        // And: Base has sufficient balances.
        // forge-lint: disable-next-item(divide-before-multiply,unsafe-typecast)
        balance1 = uint128(bound(balance1, amountIn * 11 / 10 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        PositionState memory position_;
        (balances, position_) = base.swapViaPool(balances, position, false, amountOut_);

        // Then: The correct balances are returned.
        assertEq(amountOut_, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        // And: The sqrtPrice remains equal.
        assertEq(position_.sqrtPrice, position.sqrtPrice);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_MaxCeilingHook(
        uint128 liquidityPool,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position and a swappable amount.
        (uint256 amountOut_, uint256 amountIn) = setSwapState(liquidityPool, position, amountOut);

        // And: A hook returning the maximum fee is set on the pool.
        swapHook.setFee(SWAP_FEE_CEIL);
        setSwapHookMetadex03CL(address(poolCl), address(swapHook));

        // And: Base has balances that cover the hook fee on top of the pool fee.
        // forge-lint: disable-next-item(unsafe-typecast)
        balance0 = uint128(bound(balance0, amountIn * 2 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        (balances,) = base.swapViaPool(balances, position, true, amountOut_);

        // Then: The exact amountOut is received and the balances settle against the actual token balances.
        assertEq(amountOut_, balances[1] - balance1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        // And: The effective fee exceeds the pool fee, so the amountIn estimate is only an estimate.
        assertGe(balance0 - balances[0], amountIn);
    }

    function testFuzz_Revert_swapViaPool_ZeroToOne_RevertingHook(
        uint128 liquidityPool,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1,
        uint64 amountOut
    ) public {
        // Given: A valid position and a swappable amount.
        (uint256 amountOut_, uint256 amountIn) = setSwapState(liquidityPool, position, amountOut);

        // And: A reverting hook is set on the pool.
        swapHook.setShouldRevert(true);
        setSwapHookMetadex03CL(address(poolCl), address(swapHook));

        // And: Base has sufficient balances.
        // forge-lint: disable-next-item(unsafe-typecast)
        balance0 = uint128(bound(balance0, amountIn * 2 + 1, type(uint128).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling swapViaPool.
        // Then: It reverts with the reason of the hook.
        vm.expectRevert(bytes("HOOK"));
        base.swapViaPool(balances, position, true, amountOut_);
    }
}
