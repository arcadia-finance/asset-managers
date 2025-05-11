/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer, RebalanceParams } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "_swapViaPool" of contract "RebalancerSlipstream".
 */
contract SwapViaPool_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_swapViaPool_ZeroToOne_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
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
        vm.assume(token1.balanceOf(address(poolCl)) > 1e6);
        amountOut = uint64(bound(amountOut, 1e5, token1.balanceOf(address(poolCl)) / 10));

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew =
            SqrtPriceMath.getNextSqrtPriceFromOutput(uint160(position.sqrtPrice), poolCl.liquidity(), amountOut, true);
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount0Delta(sqrtPriceNew, uint160(position.sqrtPrice), poolCl.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - poolCl.fee());
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

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams.zeroToOne, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[1] - balance1);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance0 - balances[0], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPrice remains equal.
        assertEq(position_.sqrtPrice, position.sqrtPrice);
    }

    function testFuzz_Success_swapViaPool_OneToZero_Balanced(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        RebalanceParams memory rebalanceParams,
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
        amountOut = uint64(bound(amountOut, 1e5, token0.balanceOf(address(poolCl)) / 10));

        // Get the new sqrtPrice and amountIn.
        uint160 sqrtPriceNew =
            SqrtPriceMath.getNextSqrtPriceFromOutput(uint160(position.sqrtPrice), poolCl.liquidity(), amountOut, false);
        uint256 amountInLessFee =
            SqrtPriceMath.getAmount1Delta(sqrtPriceNew, uint160(position.sqrtPrice), poolCl.liquidity(), true);
        uint256 amountIn = amountInLessFee * 1e6 / (1e6 - poolCl.fee());
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

        // When: Calling swapViaPool.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaPool(balances, position, rebalanceParams.zeroToOne, amountOut);

        // Then: The correct balances are returned.
        assertEq(amountOut, balances[0] - balance0);
        if (amountIn > 1e5) assertApproxEqRel(amountIn, balance1 - balances[1], 0.01 * 1e18);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPrice remains equal.
        assertEq(position_.sqrtPrice, position.sqrtPrice);
    }
}
