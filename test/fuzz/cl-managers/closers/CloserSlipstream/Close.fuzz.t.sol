/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountV3 } from "../../../../../lib/accounts-v2/src/accounts/AccountV3.sol";
import { AccountV4 } from "../../../../../lib/accounts-v2/src/accounts/AccountV4.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserSlipstream_Fuzz_Test } from "./_CloserSlipstream.fuzz.t.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import {
    FixedPoint128
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { ICLGauge } from "../../../../../lib/accounts-v2/src/asset-modules/Slipstream/interfaces/ICLGauge.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "close" of contract "CloserSlipstream".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Close_CloserSlipstream_Fuzz_Test is CloserSlipstream_Fuzz_Test {
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

    function testFuzz_Revert_close_Paused(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Closer is paused.
        vm.prank(users.owner);
        closer.setPauseFlag(true);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Guardian.Paused.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_Reentered(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));

        // And: account is set (triggering reentry guard).
        closer.setAccount(account_);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.Reentered.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidInitiator(Closer.InitiatorParams memory initiatorParams, address caller_)
        public
    {
        // Given: Caller is not address(0).
        vm.assume(caller_ != address(0));

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidPositionManager(
        Closer.InitiatorParams memory initiatorParams,
        address invalidPositionManager
    ) public {
        // Given: An invalid position manager (not whitelisted).
        vm.assume(invalidPositionManager != address(slipstreamPositionManager));
        vm.assume(invalidPositionManager != address(stakedSlipstreamAM));
        vm.assume(invalidPositionManager != address(wrappedStakedSlipstream));
        initiatorParams.positionManager = invalidPositionManager;

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // When: Calling close() with invalid position manager.
        // Then: it should revert.
        vm.startPrank(users.accountOwner);
        vm.expectRevert(Closer.InvalidPositionManager.selector);
        closer.close(address(account), initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidClaimFee(
        uint96 id,
        uint256 withdrawAmount,
        uint256 maxRepayAmount,
        uint256 claimFee,
        uint128 liquidity
    ) public {
        // Given: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // Given: Claim fee is invalid (above maximum).
        claimFee = bound(claimFee, MAX_CLAIM_FEE + 1, type(uint256).max);

        Closer.InitiatorParams memory initiatorParams = Closer.InitiatorParams({
            positionManager: address(slipstreamPositionManager),
            id: id,
            withdrawAmount: withdrawAmount,
            maxRepayAmount: maxRepayAmount,
            claimFee: claimFee,
            liquidity: liquidity
        });

        // When: Calling close with invalid claimFee.
        // Then: It should revert.
        vm.prank(users.accountOwner);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_InvalidWithdrawAmount(
        uint96 id,
        uint256 withdrawAmount,
        uint256 maxRepayAmount,
        uint256 claimFee,
        uint128 liquidity
    ) public {
        // Given: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // Given: Fees are valid.
        claimFee = bound(claimFee, 0, MAX_CLAIM_FEE);

        // Given: withdrawAmount is greater than maxRepayAmount.
        maxRepayAmount = bound(maxRepayAmount, 0, type(uint256).max - 1);
        withdrawAmount = bound(withdrawAmount, maxRepayAmount + 1, type(uint256).max);

        Closer.InitiatorParams memory initiatorParams = Closer.InitiatorParams({
            positionManager: address(slipstreamPositionManager),
            id: id,
            withdrawAmount: withdrawAmount,
            maxRepayAmount: maxRepayAmount,
            claimFee: claimFee,
            liquidity: liquidity
        });

        // When: Calling close with invalid withdrawAmount.
        // Then: It should revert.
        vm.prank(users.accountOwner);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_ChangeAccountOwnership(
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        address newOwner
    ) public canReceiveERC721(newOwner) {
        // Given: newOwner is not the zero address and differs from the actual owner.
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != users.accountOwner);
        vm.assume(newOwner != address(account));
        vm.assume(initiator != address(0));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = 0;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When: calling close.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Success_close_Slipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Slipstream is allowed.
        deploySlipstreamAM();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager))
            .transferFrom(users.liquidityProvider, users.accountOwner, position.id);

        // And: Account owns the position.
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);
        assets_[0] = address(slipstreamPositionManager);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        vm.startPrank(users.accountOwner);
        ERC721(address(slipstreamPositionManager)).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is back in account if not fully burned.
        if (initiatorParams.liquidity < position.liquidity) {
            assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(account));
        }
    }

    function testFuzz_Success_close_StakedSlipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.id = uint96(position.id);

        // And: Slipstream is allowed.
        deploySlipstreamAM();

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));

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

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);
        assets_[0] = address(stakedSlipstreamAM);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        vm.startPrank(users.accountOwner);
        ERC721(address(stakedSlipstreamAM)).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is back in account if not fully burned.
        if (initiatorParams.liquidity < position.liquidity) {
            assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(position.id), address(account));
        }
    }

    function testFuzz_Success_close_Slipstream_WithDebtRepayment(
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
        registry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(slipstreamAM), type(uint112).max, 10_000
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
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.id = uint96(positionId);

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, liquidity));

        // And: Debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account owns the position, has withdrawAmount of numeraire, and is a margin account.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, positionId);
        deal(address(token1), users.accountOwner, initiatorParams.withdrawAmount);
        address[] memory assets_ = new address[](2);
        uint256[] memory assetIds_ = new uint256[](2);
        uint256[] memory assetAmounts_ = new uint256[](2);
        assets_[0] = address(slipstreamPositionManager);
        assetIds_[0] = positionId;
        assetAmounts_[0] = 1;
        assets_[1] = address(token1);
        assetIds_[1] = 0;
        assetAmounts_[1] = initiatorParams.withdrawAmount;
        vm.startPrank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));
        ERC721(address(slipstreamPositionManager)).approve(address(account), positionId);
        token1.approve(address(account), initiatorParams.withdrawAmount);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // And: Debt is bounded by the collateral value to ensure account is healthy.
        uint256 collateralValue = account.getCollateralValue();
        debt = bound(debt, 1, collateralValue > 1 ? collateralValue - 1 : 1);
        lendingPoolMock.setDebt(address(account), debt);

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Debt should be reduced or stay the same.
        assertLe(lendingPoolMock.debt(address(account)), debt);
    }

    function testFuzz_Success_close_StakedSlipstream_WithDebtRepayment(
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
        registry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(slipstreamAM), type(uint112).max, 10_000
        );
        registry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(stakedSlipstreamAM), type(uint112).max, 10_000
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
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.id = uint96(positionId);

        // And: Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), positionId);
        stakedSlipstreamAM.mint(positionId);
        vm.stopPrank();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, liquidity));

        // And: Debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

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

        // And: Account owns the position, has withdrawAmount of numeraire, and is a margin account.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, users.accountOwner, positionId);
        deal(address(token1), users.accountOwner, initiatorParams.withdrawAmount);
        address[] memory assets_ = new address[](2);
        uint256[] memory assetIds_ = new uint256[](2);
        uint256[] memory assetAmounts_ = new uint256[](2);
        assets_[0] = address(stakedSlipstreamAM);
        assetIds_[0] = positionId;
        assetAmounts_[0] = 1;
        assets_[1] = address(token1);
        assetIds_[1] = 0;
        assetAmounts_[1] = initiatorParams.withdrawAmount;
        vm.startPrank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));
        ERC721(address(stakedSlipstreamAM)).approve(address(account), positionId);
        token1.approve(address(account), initiatorParams.withdrawAmount);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // And: Debt is bounded by the collateral value to ensure account is healthy.
        uint256 collateralValue = account.getCollateralValue();
        debt = bound(debt, 1, collateralValue > 1 ? collateralValue - 1 : 1);
        lendingPoolMock.setDebt(address(account), debt);

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Debt should be reduced or stay the same.
        assertLe(lendingPoolMock.debt(address(account)), debt);
    }

    function testFuzz_Success_close_WrappedStakedSlipstream(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
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

        // And: Spot Account is used (wrappedStakedSlipstream is not a registered Asset Module).
        vm.prank(users.accountOwner);
        account = AccountV3(address(new AccountV4(address(factory), address(accountsGuard), address(0))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));

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

        // And: Account owns the position (transferred directly, not via deposit).
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), position.id);

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is back in account if not fully burned.
        if (initiatorParams.liquidity < position.liquidity) {
            assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(position.id), address(account));
        }
    }
}
