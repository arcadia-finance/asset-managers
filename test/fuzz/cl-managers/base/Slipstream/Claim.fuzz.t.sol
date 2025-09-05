/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../../../../../src/cl-managers/base/AbstractBase.sol";
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
 * @notice Fuzz tests for the function "_claim" of contract "Slipstream".
 */
contract Claim_Slipstream_Fuzz_Test is Slipstream_Fuzz_Test {
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
    function testFuzz_Success_claim_Slipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint80 swap0,
        uint80 swap1,
        uint256 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // And: position has fees.
        generateFees(swap0, swap1);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token0), fee0);
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token1), fee1);
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, address(slipstreamPositionManager), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], uint256(balance0) + fee0);
        assertEq(balances[1], uint256(balance1) + fee1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], fee0 * claimFee / 1e18);
        assertEq(fees[1], fee1 * claimFee / 1e18);
    }

    function testFuzz_Success_claim_StakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

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
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
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
            if (claimFee > 0) vm.assume(rewards < type(uint256).max / claimFee);
        }

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), AERO, rewards);
        uint256[] memory fees = new uint256[](balances.length);
        (balances, fees) = base.claim(balances, fees, address(stakedSlipstreamAM), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(base)));

        assertEq(fees[0], 0);
        assertEq(fees[1], 0);
        assertEq(fees[2], rewards * claimFee / 1e18);
    }

    function testFuzz_Success_claim_StakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        bytes32 salt,
        uint256 claimFee
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

        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

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
            if (claimFee > 0) vm.assume(rewards < type(uint256).max / claimFee);
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
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), AERO, rewards);
        uint256[] memory fees = new uint256[](balances.length);
        (balances, fees) = base.claim(balances, fees, address(stakedSlipstreamAM), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], (address(token0) == AERO ? rewards * claimFee / 1e18 : 0));
        assertEq(fees[1], (address(token1) == AERO ? rewards * claimFee / 1e18 : 0));
    }

    function testFuzz_Success_claim_WrappedStakedSlipstream_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

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
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
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
            if (claimFee > 0) vm.assume(rewards < type(uint256).max / claimFee);
        }

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), AERO, rewards);
        uint256[] memory fees = new uint256[](balances.length);
        (balances, fees) = base.claim(balances, fees, address(wrappedStakedSlipstream), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[2], rewards);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
        assertEq(balances[2], ERC20(AERO).balanceOf(address(base)));

        assertEq(fees[0], 0);
        assertEq(fees[1], 0);
        assertEq(fees[2], rewards * claimFee / 1e18);
    }

    function testFuzz_Success_claim_WrappedStakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        bytes32 salt,
        uint64 claimFee
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

        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

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
            if (claimFee > 0) vm.assume(rewards < type(uint256).max / claimFee);
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
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Position earned rewards.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), rewards, true);
        stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), AERO, rewards);
        uint256[] memory fees = new uint256[](balances.length);
        (balances, fees) = base.claim(balances, fees, address(wrappedStakedSlipstream), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0 + (address(token0) == AERO ? rewards : 0));
        assertEq(balances[1], balance1 + (address(token1) == AERO ? rewards : 0));
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], (address(token0) == AERO ? rewards * claimFee / 1e18 : 0));
        assertEq(fees[1], (address(token1) == AERO ? rewards * claimFee / 1e18 : 0));
    }
}
