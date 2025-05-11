/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_burn" of contract "RebalancerSlipstream".
 */
contract Burn_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_burn_Slipstream(
        uint128 liquidityPool,
        PositionState memory position,
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
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(rebalancer), position.id
        );

        // When: Calling burn.
        balances = rebalancer.burn(balances, address(slipstreamPositionManager), position);

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

    function testFuzz_Success_burn_StakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling burn.
        balances = rebalancer.burn(balances, address(stakedSlipstreamAM), position);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        uint256 rewards;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPrice
                && position.sqrtPrice < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewards = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        assertEq(balances[0], balance0 + amount0);
        assertEq(balances[1], balance1 + amount1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_burn_StakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        bytes32 salt
    ) public {
        // Given: Aero is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Aero does not overflow.
        uint256 rewards;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPrice
                && position.sqrtPrice < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewards = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        if (address(token0) == AERO) {
            balance0 = uint64(bound(balance0, 0, type(uint256).max - rewards));
        } else {
            balance1 = uint64(bound(balance1, 0, type(uint256).max - rewards));
        }

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling burn.
        balances = rebalancer.burn(balances, address(stakedSlipstreamAM), position);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        assertEq(balances[0], balance0 + amount0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + amount1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_burn_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling burn.
        balances = rebalancer.burn(balances, address(wrappedStakedSlipstream), position);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        uint256 rewards;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPrice
                && position.sqrtPrice < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewards = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        assertEq(balances[0], balance0 + amount0);
        assertEq(balances[1], balance1 + amount1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_burn_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        bytes32 salt
    ) public {
        // Given: Aero is an underlying token of the position.
        token0 = new ERC20Mock{ salt: salt }("TokenA", "TOKA", 0);
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And : An initial rewardGrowthGlobalX128.
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Aero does not overflow.
        uint256 rewards;
        if (
            TickMath.getSqrtPriceAtTick(position.tickLower) < position.sqrtPrice
                && position.sqrtPrice < TickMath.getSqrtPriceAtTick(position.tickUpper)
        ) {
            uint256 rewardGrowthInsideX128;
            unchecked {
                rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
            }
            rewards = FullMath.mulDiv(rewardGrowthInsideX128, position.liquidity, FixedPoint128.Q128);
        }
        if (address(token0) == AERO) {
            balance0 = uint64(bound(balance0, 0, type(uint256).max - rewards));
        } else {
            balance1 = uint64(bound(balance1, 0, type(uint256).max - rewards));
        }

        // And: Rebalancer has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // Transfer position to Rebalancer.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(rebalancer), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling burn.
        balances = rebalancer.burn(balances, address(wrappedStakedSlipstream), position);

        // Then: It should return the correct balances.
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPrice),
            TickMath.getSqrtPriceAtTick(position.tickLower),
            TickMath.getSqrtPriceAtTick(position.tickUpper),
            position.liquidity
        );
        assertEq(balances[0], balance0 + amount0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + amount1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }
}
