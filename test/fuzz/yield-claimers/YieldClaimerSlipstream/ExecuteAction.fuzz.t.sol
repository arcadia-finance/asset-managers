/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData } from "../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../src/libraries/RebalanceLogic.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceMock } from "../../../utils/mocks/RouterSetPoolPriceMock.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimerSlipstream_Fuzz_Test } from "./_YieldClaimerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "YieldClaimerSlipstream".
 */
contract ExecuteAction_YieldClaimerSlipstream_Fuzz_Test is YieldClaimerSlipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        YieldClaimerSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: account is set.
        yieldClaimer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(YieldClaimer.OnlyAccount.selector);
        yieldClaimer.executeAction(rebalanceData);
        vm.stopPrank();
    }

    function testFuzz_Success_executeAction_Slipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(yieldClaimer), position.id
        );

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(slipstreamPositionManager), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        uint256 index = 1;
        if (fee0 > 0) {
            assertEq(depositData.assets[1], address(token0));
            assertEq(depositData.assetIds[1], 0);
            assertEq(depositData.assetAmounts[1], fee0 - fee0 * initiatorParams.claimFee / 1e18);
            assertEq(depositData.assetTypes[1], 1);
            index++;
        }
        if (fee1 > 0) {
            assertEq(depositData.assets[index], address(token1));
            assertEq(depositData.assetIds[index], 0);
            assertEq(depositData.assetAmounts[index], fee1 - fee1 * initiatorParams.claimFee / 1e18);
            assertEq(depositData.assetTypes[index], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(slipstreamPositionManager)).getApproved(position.id), address(account));
        assertEq(
            token0.allowance(address(yieldClaimer), address(account)), fee0 - fee0 * initiatorParams.claimFee / 1e18
        );
        assertEq(
            token1.allowance(address(yieldClaimer), address(account)), fee1 - fee1 * initiatorParams.claimFee / 1e18
        );

        // And: Initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_executeAction_Slipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(account));
        vm.assume(recipient != address(0));

        // And: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, address(yieldClaimer), position.id
        );

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(slipstreamPositionManager), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(slipstreamPositionManager)).getApproved(position.id), address(account));

        // And: recipient received the fees.
        assertEq(token0.balanceOf(recipient), fee0 - fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(recipient), fee1 - fee1 * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.id = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(yieldClaimer), position.id);

        // And: Position earned rewards.
        rewards = bound(rewards, 0, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }
        rewards = stakedSlipstreamAM.rewardOf(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(stakedSlipstreamAM), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        if (rewards > 0) {
            assertEq(depositData.assets[1], AERO);
            assertEq(depositData.assetIds[1], 0);
            assertEq(depositData.assetAmounts[1], rewards - rewards * initiatorParams.claimFee / 1e18);
            assertEq(depositData.assetTypes[1], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(position.id), address(account));
        assertEq(
            ERC20(AERO).allowance(address(yieldClaimer), address(account)),
            rewards - rewards * initiatorParams.claimFee / 1e18
        );

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // Given: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(account));
        vm.assume(recipient != address(0));

        // And: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.id = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(yieldClaimer), position.id);

        // And: Position earned rewards.
        rewards = bound(rewards, 0, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }
        rewards = stakedSlipstreamAM.rewardOf(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(stakedSlipstreamAM), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(stakedSlipstreamAM)).getApproved(position.id), address(account));

        // And: recipient received the rewards.
        assertEq(ERC20(AERO).balanceOf(recipient), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(wrappedStakedSlipstream);
        initiatorParams.id = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(
            users.liquidityProvider, address(yieldClaimer), position.id
        );

        // And: Position earned rewards.
        rewards = bound(rewards, 0, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }
        rewards = wrappedStakedSlipstream.rewardOf(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(wrappedStakedSlipstream), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        if (rewards > 0) {
            assertEq(depositData.assets[1], AERO);
            assertEq(depositData.assetIds[1], 0);
            assertEq(depositData.assetAmounts[1], rewards - rewards * initiatorParams.claimFee / 1e18);
            assertEq(depositData.assetTypes[1], 1);
        }

        // And: Approvals are given.
        assertEq(ERC721(address(wrappedStakedSlipstream)).getApproved(position.id), address(account));
        assertEq(
            ERC20(AERO).allowance(address(yieldClaimer), address(account)),
            rewards - rewards * initiatorParams.claimFee / 1e18
        );

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // And: recipient is not the account or address(0).
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(account));
        vm.assume(recipient != address(0));

        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(wrappedStakedSlipstream);
        initiatorParams.id = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: The YieldClaimer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(
            users.liquidityProvider, address(yieldClaimer), position.id
        );

        // And: Position earned rewards.
        rewards = bound(rewards, 0, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector).checked_write(
                rewardGrowthGlobalX128Current
            );
        }
        rewards = wrappedStakedSlipstream.rewardOf(position.id);

        // And: account is set.
        yieldClaimer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(wrappedStakedSlipstream), position.id);
        ActionData memory depositData = yieldClaimer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: Approvals are given.
        assertEq(ERC721(address(wrappedStakedSlipstream)).getApproved(position.id), address(account));

        // And: recipient received the rewards.
        assertEq(ERC20(AERO).balanceOf(recipient), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }
}
