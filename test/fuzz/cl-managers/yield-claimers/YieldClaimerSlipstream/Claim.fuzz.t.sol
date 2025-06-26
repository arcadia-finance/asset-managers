/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AccountV1 } from "../../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { AccountSpot } from "../../../../../lib/accounts-v2/src/accounts/AccountSpot.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { YieldClaimer } from "../../../../../src/cl-managers/yield-claimers/YieldClaimer.sol";
import { YieldClaimerSlipstream_Fuzz_Test } from "./_YieldClaimerSlipstream.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimerSlipstream".
 */
contract Compound_YieldClaimerSlipstream_Fuzz_Test is YieldClaimerSlipstream_Fuzz_Test {
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
    function testFuzz_Revert_claim_Reentered(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        yieldClaimer.setAccount(account_);

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.Reentered.selector);
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidAccount(
        address account_,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        yieldClaimer.claim(account_, initiatorParams);
    }

    function testFuzz_Revert_claim_InvalidInitiator(YieldClaimer.InitiatorParams memory initiatorParams, address caller)
        public
    {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling claim
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), initiatorParams);
    }

    function testFuzz_Revert_claim_ChangeAccountOwnership(
        YieldClaimer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: YieldClaimer is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: YieldClaimer is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: Account is transferred to newOwner.
        vm.startPrank(account.owner());
        factory.safeTransferFrom(account.owner(), newOwner, address(account));
        vm.stopPrank();

        // When : calling claim
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(YieldClaimer.InvalidInitiator.selector);
        yieldClaimer.claim(address(account), initiatorParams);
    }

    function testFuzz_Success_claim_Slipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, address(account), MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, users.accountOwner, position.id
        );
        {
            address[] memory assets_ = new address[](1);
            uint256[] memory assetIds_ = new uint256[](1);
            uint256[] memory assetAmounts_ = new uint256[](1);

            assets_[0] = address(slipstreamPositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), position.id);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(account));

        // And: tokens are deposited back into the account.
        assertEq(token0.balanceOf(address(account)), fee0 - fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(address(account)), fee1 - fee1 * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_claim_Slipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // Given: recipient is not holdig balances.
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(0));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And: Account info is set.
        vm.prank(account.owner());
        yieldClaimer.setAccountInfo(address(account), initiator, recipient, MAX_FEE, "");

        // And: Fee is valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(
            users.liquidityProvider, users.accountOwner, position.id
        );
        {
            address[] memory assets_ = new address[](1);
            uint256[] memory assetIds_ = new uint256[](1);
            uint256[] memory assetAmounts_ = new uint256[](1);

            assets_[0] = address(slipstreamPositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), position.id);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id), address(account));

        // And: recipient received the fees.
        assertEq(token0.balanceOf(recipient), fee0 - fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(recipient), fee1 - fee1 * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(token0.balanceOf(initiator), fee0 * initiatorParams.claimFee / 1e18);
        assertEq(token1.balanceOf(initiator), fee1 * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_claim_StakedSlipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

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

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        {
            address[] memory assets_ = new address[](1);
            uint256[] memory assetIds_ = new uint256[](1);
            uint256[] memory assetAmounts_ = new uint256[](1);

            assets_[0] = address(stakedSlipstreamAM);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(stakedSlipstreamAM)).approve(address(account), position.id);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(position.id), address(account));

        // And: rewards are deposited back into the account.
        assertEq(ERC20(AERO).balanceOf(address(account)), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_claim_StakedSlipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not the account or address(0).
        // Given: recipient is not holdig balances.
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(0));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

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

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        {
            address[] memory assets_ = new address[](1);
            uint256[] memory assetIds_ = new uint256[](1);
            uint256[] memory assetAmounts_ = new uint256[](1);

            assets_[0] = address(stakedSlipstreamAM);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(stakedSlipstreamAM)).approve(address(account), position.id);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(position.id), address(account));

        // And: rewards are deposited back into the account.
        assertEq(ERC20(AERO).balanceOf(recipient), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_claim_WrappedStakedSlipstream_AccountIsRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: Spot Account is used.
        vm.prank(users.accountOwner);
        account = AccountV1(address(new AccountSpot(address(factory))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

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

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), position.id);

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(position.id), address(account));

        // And: rewards are deposited back into the account.
        assertEq(ERC20(AERO).balanceOf(address(account)), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }

    function testFuzz_Success_claim_WrappedStakedSlipstream_AccountIsNotRecipient(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        YieldClaimer.InitiatorParams memory initiatorParams,
        address initiator,
        address recipient
    ) public {
        // Given: initiator is not holdig balances.
        vm.assume(initiator != address(yieldClaimer));
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(account));

        // And: recipient is not the account or address(0).
        // Given: recipient is not holdig balances.
        vm.assume(recipient != address(yieldClaimer));
        vm.assume(recipient != users.liquidityProvider);
        vm.assume(recipient != address(account));
        vm.assume(recipient != initiator);
        vm.assume(recipient != address(0));

        // And: A valid position in range (has both tokens).
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

        // And: uniV3 is allowed.
        deploySlipstreamAM();

        // And: Spot Account is used.
        vm.prank(users.accountOwner);
        account = AccountV1(address(new AccountSpot(address(factory))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));

        // And: YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

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

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), position.id);

        // When: Calling claim().
        vm.prank(initiator);
        yieldClaimer.claim(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(position.id), address(account));

        // And: rewards are deposited back into the account.
        assertEq(ERC20(AERO).balanceOf(recipient), rewards - rewards * initiatorParams.claimFee / 1e18);

        // And: Initiator fees are given.
        assertEq(ERC20(AERO).balanceOf(initiator), rewards * initiatorParams.claimFee / 1e18);
    }
}
