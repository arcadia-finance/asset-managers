/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserSlipstream_Fuzz_Test } from "./_CloserSlipstream.fuzz.t.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import {
    FixedPoint128
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { ICLGauge } from "../../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "CloserSlipstream".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ExecuteAction_CloserSlipstream_Fuzz_Test is CloserSlipstream_Fuzz_Test {
    using stdStorage for StdStorage;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CloserSlipstream_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_executeAction_NonAccount(bytes calldata actionTargetData, address caller_) public {
        // Given: Caller is not the account.
        vm.assume(caller_ != address(account));

        // And: account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.OnlyAccount.selector);
        closer.executeAction(actionTargetData);
        vm.stopPrank();
    }

    function testFuzz_Success_executeAction_Slipstream_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
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
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Only claim, no liquidity change.
        initiatorParams.liquidity = 0;

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_Slipstream_DecreasePosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
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
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(slipstreamPositionManager), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(slipstreamPositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_Slipstream_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
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
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, position.liquidity, type(uint128).max));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(slipstreamPositionManager), position.id);
        closer.executeAction(actionTargetData);

        // And: Position is burned.
        vm.expectRevert();
        ERC721(address(slipstreamPositionManager)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_Slipstream_WithDebtRepayment(
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint128 liquidity,
        uint256 debt
    ) public {
        // Given: Pool and assets.
        initSlipstream(2 ** 96, 1e18, TICK_SPACING);
        deploySlipstreamAM();

        // And: Lending pool and risk parameters.
        LendingPoolMock lendingPoolMock = new LendingPoolMock(address(token1));
        lendingPoolMock.setRiskManager(users.riskManager);
        vm.startPrank(users.riskManager);
        registry.setRiskParameters(address(lendingPoolMock), 0, 0, type(uint64).max);
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token0), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token1), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfDerivedAM(address(lendingPoolMock), address(slipstreamAM), type(uint112).max, 100);
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        liquidity = uint128(bound(liquidity, 1e10, 1e12));
        (uint256 positionId,,) = addLiquidityCL(
            poolCl,
            liquidity,
            users.liquidityProvider,
            -10_000 / TICK_SPACING * TICK_SPACING,
            10_000 / TICK_SPACING * TICK_SPACING,
            false
        );
        initiatorParams.id = uint96(positionId);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, liquidity, type(uint128).max));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.positionManager = address(slipstreamPositionManager);

        // And: debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

        // And: Position has debt.
        debt = bound(debt, 1, 1e8);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, address(closer), positionId);

        // And: Withdraw amount is minted to the Closer.
        deal(address(token1), address(closer), initiatorParams.withdrawAmount);

        // And: Account is set and is a margin account.
        closer.setAccount(address(account));
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Debt should be reduced correctly.
        // If maxRepayAmount is 0, debt stays the same. Otherwise debt is reduced.
        if (initiatorParams.maxRepayAmount == 0) {
            assertEq(lendingPoolMock.debt(address(account)), debt);
        } else {
            assertLt(lendingPoolMock.debt(address(account)), debt);
        }
    }

    function testFuzz_Success_executeAction_StakedSlipstream_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Only claim, no liquidity change.
        initiatorParams.liquidity = 0;

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_DecreasePosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(stakedSlipstreamAM), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, position.liquidity, type(uint128).max));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Position is burned.
        vm.expectRevert();
        ERC721(address(slipstreamPositionManager)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_WithDebtRepayment(
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint128 liquidity,
        uint256 debt,
        uint256 rewards
    ) public {
        // Given: Pool and assets.
        initSlipstream(2 ** 96, 1e18, TICK_SPACING);
        deploySlipstreamAM();

        // And: Create gauge for the pool (required for staked positions).
        vm.prank(address(voter));
        gauge = ICLGauge(cLGaugeFactory.createGauge(address(0), address(poolCl), address(0), AERO, true));
        voter.setGauge(address(poolCl), address(gauge));
        voter.setAlive(address(gauge), true);
        vm.prank(users.owner);
        stakedSlipstreamAM.addGauge(address(gauge));

        // And: Lending pool and risk parameters.
        LendingPoolMock lendingPoolMock = new LendingPoolMock(address(token1));
        lendingPoolMock.setRiskManager(users.riskManager);
        vm.startPrank(users.riskManager);
        registry.setRiskParameters(address(lendingPoolMock), 0, 0, type(uint64).max);
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token0), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token1), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfPrimaryAsset(address(lendingPoolMock), AERO, 0, type(uint112).max, 9000, 9500);
        registry.setRiskParametersOfDerivedAM(address(lendingPoolMock), address(slipstreamAM), type(uint112).max, 100);
        registry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(stakedSlipstreamAM), type(uint112).max, 100
        );
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        liquidity = uint128(bound(liquidity, 1e10, 1e12));
        (uint256 positionId,,) = addLiquidityCL(
            poolCl,
            liquidity,
            users.liquidityProvider,
            -10_000 / TICK_SPACING * TICK_SPACING,
            10_000 / TICK_SPACING * TICK_SPACING,
            false
        );
        initiatorParams.id = uint96(positionId);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, liquidity, type(uint128).max));

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), positionId);
        stakedSlipstreamAM.mint(positionId);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.positionManager = address(stakedSlipstreamAM);

        // And: debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

        // And: Position has debt.
        debt = bound(debt, 1, 1e8);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), positionId);

        // And: Withdraw amount is minted to the Closer.
        deal(address(token1), address(closer), initiatorParams.withdrawAmount);

        // And: Account is set and is a margin account.
        closer.setAccount(address(account));
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Debt should be reduced correctly.
        // If maxRepayAmount is 0, debt stays the same. Otherwise debt is reduced.
        if (initiatorParams.maxRepayAmount == 0) {
            assertEq(lendingPoolMock.debt(address(account)), debt);
        } else {
            assertLt(lendingPoolMock.debt(address(account)), debt);
        }
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenIsNumeraire(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction() with AERO (reward token) as numeraire.
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, AERO, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(stakedSlipstreamAM), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_StakedSlipstream_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: AERO is an underlying token of the position (2 underlying tokens).
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: Valid pool and position.
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

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), rewards, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(stakedSlipstreamAM), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(stakedSlipstreamAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_DecreasePosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create wrapped staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(wrappedStakedSlipstream), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create wrapped staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Only claim, no liquidity change.
        initiatorParams.liquidity = 0;

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position (reward token is NOT token0 or token1 - 3 underlying tokens).
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

        // And: Create wrapped staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, position.liquidity, type(uint128).max));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), type(uint256).max, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Position is burned.
        vm.expectRevert();
        ERC721(address(slipstreamPositionManager)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_WrappedStakedSlipstream_DecreasePosition_RewardTokenIsToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: AERO is an underlying token of the position (2 underlying tokens).
        token1 = ERC20Mock(AERO);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        stdstore.target(address(registry)).sig(registry.inRegistry.selector).with_key(AERO).checked_write(false);

        // And: Valid pool and position.
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

        // And: Create wrapped staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        {
            uint256 rewardGrowthGlobalX128Current = FullMath.mulDiv(rewards, FixedPoint128.Q128, position.liquidity);
            vm.warp(block.timestamp + 1);
            deal(AERO, address(gauge), rewards, true);
            stdstore.target(address(poolCl)).sig(poolCl.rewardReserve.selector).checked_write(type(uint256).max);
            stdstore.target(address(poolCl)).sig(poolCl.rewardGrowthGlobalX128.selector)
                .checked_write(rewardGrowthGlobalX128Current);
        }

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(wrappedStakedSlipstream), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(wrappedStakedSlipstream));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }
}
