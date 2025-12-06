/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountV3 } from "../../../../../lib/accounts-v2/src/accounts/AccountV3.sol";
import { AccountV4 } from "../../../../../lib/accounts-v2/src/accounts/AccountV4.sol";
import { DefaultHook } from "../../../../utils/mocks/DefaultHook.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import {
    FixedPoint128
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { RebalancerSlipstream_Fuzz_Test } from "./_RebalancerSlipstream.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "RebalancerSlipstream".
 */
contract Rebalance_RebalancerSlipstream_Fuzz_Test is RebalancerSlipstream_Fuzz_Test {
    using stdStorage for StdStorage;
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSlipstream_Fuzz_Test.setUp();

        strategyHook = new DefaultHook();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalance_Paused(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Rebalancer is Paused.
        vm.prank(users.owner);
        rebalancer.setPauseFlag(true);

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_Reentered(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_InvalidAccount(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_InvalidInitiator(
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.InvalidInitiator.selector);
        rebalancer.rebalance(address(account), initiatorParams);
    }

    function testFuzz_Revert_rebalance_ChangeAccountOwnership(
        Rebalancer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator,
        uint256 tolerance
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Rebalancer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(rebalancer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Rebalancer is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling rebalance
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidInitiator.selector);
        rebalancer.rebalance(address(account), initiatorParams);
    }

    function testFuzz_Success_rebalance_Slipstream(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        (uint256 amount0, uint256 amount1) = setPositionState(position);
        initiatorParams.positionManager = address(slipstreamPositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Slipstream is allowed.
        deploySlipstreamAM();

        // And: Rebalancer is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(rebalancer);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A valid new position.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 10_000));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10_000, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Limited leftovers.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, type(uint8).max));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, type(uint8).max));

        // And: Withdrawn amount is smaller than the positions balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(slipstreamPositionManager))
            .transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        // forge-lint: disable-end(erc20-unchecked-transfer)
        deal(address(token0), users.accountOwner, initiatorParams.amountIn0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amountIn1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(slipstreamPositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amountIn0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amountIn1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amountIn0);
            token1.approve(address(account), initiatorParams.amountIn1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(slipstreamPositionManager)).ownerOf(position.id + 1), address(account));

        // And: Account balances should be correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }

    function testFuzz_Success_rebalance_StakedSlipstream(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        (uint256 amount0, uint256 amount1) = setPositionState(position);
        initiatorParams.positionManager = address(stakedSlipstreamAM);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), position.id);
        stakedSlipstreamAM.mint(position.id);
        vm.stopPrank();

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

        // And: Rebalancer is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(rebalancer);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A valid new position.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 10_000));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10_000, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Limited leftovers.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, type(uint8).max));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, type(uint8).max));

        // And: Withdrawn amount is smaller than the positions balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(stakedSlipstreamAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amountIn0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amountIn1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(stakedSlipstreamAM);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amountIn0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amountIn1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(stakedSlipstreamAM)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amountIn0);
            token1.approve(address(account), initiatorParams.amountIn1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(position.id + 1), address(account));

        // And: Account balances should be correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }

    function testFuzz_Success_rebalance_WrappedStakedSlipstream(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        (uint256 amount0, uint256 amount1) = setPositionState(position);
        initiatorParams.positionManager = address(wrappedStakedSlipstream);
        initiatorParams.oldId = uint96(position.id);

        // Create staked position.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), position.id);
        wrappedStakedSlipstream.mint(position.id);
        vm.stopPrank();

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

        // And: Spot Account is used.
        vm.prank(users.accountOwner);
        account = AccountV3(address(new AccountV4(address(factory), address(accountsGuard), address(0))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));

        // And: Rebalancer is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(rebalancer);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: A valid new position.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 10_000));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10_000, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Limited leftovers.
        initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, 0, type(uint8).max));
        initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, 0, type(uint8).max));

        // And: Withdrawn amount is smaller than the positions balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), position.id);
        deal(address(token0), address(account), initiatorParams.amountIn0, true);
        deal(address(token1), address(account), initiatorParams.amountIn1, true);

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(position.id + 1), address(account));

        // And: Account balances should be correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }
}
