/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20, ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Slipstream_Fuzz_Test } from "./_Slipstream.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_unstake" of contract "Slipstream".
 */
contract Unstake_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Slipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_unstake_Slipstream(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling unstake.
        balances = base.unstake(balances, address(slipstreamPositionManager), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_unstake_StakedSlipstream_RewardTokenNotToken0Or1(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling unstake.
        balances = base.unstake(balances, address(stakedSlipstreamAM), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
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
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(base)));
    }

    function testFuzz_Success_unstake_StakedSlipstream_RewardTokenIsToken0Or1(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling unstake.
        balances = base.unstake(balances, address(stakedSlipstreamAM), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_unstake_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](3);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling unstake.
        balances = base.unstake(balances, address(wrappedStakedSlipstream), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
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
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(base)));
    }

    function testFuzz_Success_unstake_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
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

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling unstake.
        balances = base.unstake(balances, address(wrappedStakedSlipstream), position);

        // Then: Base should own the position.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(base));

        // And: It should return the correct balances.
        assertEq(balances[0], balance0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }
}
