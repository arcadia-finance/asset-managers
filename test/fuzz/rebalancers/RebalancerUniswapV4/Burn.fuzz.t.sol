/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { IWETH } from "../../../../src/rebalancers/interfaces/IWETH.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_burn" of contract "RebalancerUniswapV4".
 */
contract Burn_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_burn_NotNative(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // When: Calling burn.
        balances = rebalancer.burn(balances, initiatorParams, position, cache);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        assertEq(balances[0], balance0 + amount0);
        assertEq(balances[1], balance1 + amount1);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_burn_IsNative(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache,
        uint64 balance0,
        uint64 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        initiatorParams.amount0 = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        vm.prank(address(rebalancer));
        IWETH(address(weth9)).deposit{ value: balance0 }();
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // When: Calling burn.
        balances = rebalancer.burn(balances, initiatorParams, position, cache);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        assertEq(balances[0], balance0 + amount0);
        assertEq(balances[1], balance1 + amount1);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }
}
