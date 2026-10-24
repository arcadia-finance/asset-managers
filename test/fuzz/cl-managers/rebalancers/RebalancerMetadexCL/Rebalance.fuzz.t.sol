/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultRebalancerHook } from "../../../../utils/mocks/DefaultRebalancerHook.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { RebalancerMetadexCL_Fuzz_Test } from "./_RebalancerMetadexCL.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "RebalancerSlipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(divide-before-multiply,erc20-unchecked-transfer,unsafe-typecast)
contract Rebalance_RebalancerMetadexCL_Fuzz_Test is RebalancerMetadexCL_Fuzz_Test {
    using stdStorage for StdStorage;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultRebalancerHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerMetadexCL_Fuzz_Test.setUp();

        strategyHook = new DefaultRebalancerHook();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a pool with an in range position that carries both tokens.
    function setInRangePosition(uint128 liquidityPool, PositionState memory position, bool staked)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, staked);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        (amount0, amount1) = setPositionState(position);
    }

    function allowRebalancerAsAssetManager() internal {
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(rebalancer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
    }

    function setAccountInfo(address initiator, uint256 tolerance) internal {
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
    }

    function depositInAccount(address positionManager, PositionState memory position, uint128 amount0, uint128 amount1)
        internal
    {
        deal(address(token0), users.accountOwner, amount0, true);
        deal(address(token1), users.accountOwner, amount1, true);

        address[] memory assets_ = new address[](3);
        uint256[] memory assetIds_ = new uint256[](3);
        uint256[] memory assetAmounts_ = new uint256[](3);

        assets_[0] = positionManager;
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;

        assets_[1] = address(token0);
        assetAmounts_[1] = amount0;

        assets_[2] = address(token1);
        assetAmounts_[2] = amount1;

        vm.startPrank(users.accountOwner);
        ERC721(positionManager).approve(address(account), position.id);
        token0.approve(address(account), amount0);
        token1.approve(address(account), amount1);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalance_Paused(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Rebalancer is paused.
        vm.prank(users.owner);
        rebalancer.setPauseFlag(true);

        // When: Calling rebalance.
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        // Then: It reverts.
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_Reentered(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: Calling rebalance.
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        // Then: It reverts.
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_InvalidInitiator(
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Caller is not address(0).
        vm.assume(caller != address(0));

        // And: The owner of the account has not set an initiator yet.

        // When: Calling rebalance.
        vm.prank(caller);
        vm.expectRevert(Rebalancer.InvalidInitiator.selector);
        // Then: It reverts.
        rebalancer.rebalance(address(account), initiatorParams);
    }

    function testFuzz_Success_rebalance_MetadexCL(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        uint256 feeSeed,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        (uint256 amount0, uint256 amount1) = setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Rebalancer is allowed as Asset Manager.
        allowRebalancerAsAssetManager();

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE));

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

        // And: The withdrawn amount is smaller than the position balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, 0, type(uint56).max));
        generateFees(feeSeed, feeSeed);

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(
            address(metadex03PositionManager), position, initiatorParams.amountIn0, initiatorParams.amountIn1
        );

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling rebalance.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: The new position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id + 1), address(account));

        // And: The account balances are correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }

    function testFuzz_Success_rebalance_MetadexCL_PriceOnLowerTick(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, false);

        // And: A position with its lower tick on the pool price.
        position.tickLower = position.tickCurrent;
        position.tickUpper = int24(
            bound(
                position.tickUpper,
                position.tickCurrent / position.tickSpacing + 1,
                BOUND_TICK_UPPER / position.tickSpacing
            )
        ) * position.tickSpacing;

        // And: The position is large enough for the minimum liquidity ratio.
        uint256 unsold = FullMath.mulDivRoundingUp(liquidityPool, 9, 1 << 99);
        unsold = ((position.sqrtPrice >> 145) + 5) * unsold + 2
            * FullMath.mulDivRoundingUp(position.sqrtPrice, 5 * position.sqrtPrice, 1 << 194) + 5;
        uint256 minAmountIn = 2 * unsold;
        {
            uint256 minLiquidity = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPrice),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                    * (FullMath.mulDivRoundingUp(minAmountIn, 1 << 192, position.sqrtPrice * position.sqrtPrice)
                        + FullMath.mulDivRoundingUp(1, 1 << 96, position.sqrtPrice))
            ) + 1;
            vm.assume(minLiquidity <= liquidityPool / minAmountIn);
            position.liquidity = uint128(bound(position.liquidity, minLiquidity, liquidityPool / minAmountIn));
        }
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Rebalancer is allowed as Asset Manager.
        allowRebalancerAsAssetManager();

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE));

        // And: The initiator charges no swap fee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = 0;

        // And: The new position has the ticks of the old one.
        initiatorParams.strategyData = abi.encode(position.tickLower, position.tickUpper);

        // And: A token1 balance of at least twice what the swap can leave unsold.
        initiatorParams.amountIn0 = 0;
        {
            (,, uint256 upperSqrtPriceDeviation,,,) = rebalancer.accountInfo(address(account));
            uint256 maxAmountIn = FullMath.mulDiv(
                liquidityPool,
                FullMath.mulDiv(position.sqrtPrice, upperSqrtPriceDeviation, 1e18) - position.sqrtPrice - 2,
                1 << 96
            );
            maxAmountIn = FixedPointMathLib.min(maxAmountIn, liquidityPool / position.liquidity);
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                FullMath.mulDiv(
                    SqrtPriceMath.getAmount0Delta(
                            uint160(position.sqrtPrice),
                            TickMath.getSqrtPriceAtTick(position.tickUpper),
                            position.liquidity,
                            false
                        ) / (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                        - FullMath.mulDivRoundingUp(1, 1 << 96, position.sqrtPrice),
                    position.sqrtPrice * position.sqrtPrice,
                    1 << 192
                )
            );
            vm.assume(minAmountIn <= maxAmountIn);
            initiatorParams.amountIn1 = uint128(bound(initiatorParams.amountIn1, minAmountIn, maxAmountIn));
        }

        // And: Nothing is withdrawn.
        initiatorParams.amountOut0 = 0;
        initiatorParams.amountOut1 = 0;

        // And: Account owns the position and the token1 balance.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(
            address(metadex03PositionManager), position, initiatorParams.amountIn0, initiatorParams.amountIn1
        );

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling rebalance.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: The new position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id + 1), address(account));

        // And: The Rebalancer holds no tokens.
        assertEq(token0.balanceOf(address(rebalancer)), 0);
        assertEq(token1.balanceOf(address(rebalancer)), 0);

        // And: The Account holds at most the unsold token1.
        assertLe(token1.balanceOf(address(account)), unsold);
    }

    function testFuzz_Success_rebalance_MetadexCL_PriceOnUpperTick(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, false);

        // And: A position with its upper tick on the pool price.
        position.tickUpper = position.tickCurrent;
        position.tickLower = int24(
            bound(
                position.tickLower,
                BOUND_TICK_LOWER / position.tickSpacing,
                position.tickCurrent / position.tickSpacing - 1
            )
        ) * position.tickSpacing;

        // And: The position is large enough for the minimum liquidity ratio.
        uint256 unsold = FixedPointMathLib.divUp(
            FullMath.mulDivRoundingUp(liquidityPool, 5 << 94, position.sqrtPrice), position.sqrtPrice
        );
        unsold = ((position.sqrtPrice >> 145) + 5) * unsold + 2
            * FullMath.mulDivRoundingUp(5 << 190, 1, position.sqrtPrice * position.sqrtPrice) + 5;
        uint256 minAmountIn = 2 * unsold;
        {
            uint256 minLiquidity = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                uint160(position.sqrtPrice),
                (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                    * (FullMath.mulDivRoundingUp(minAmountIn, position.sqrtPrice * position.sqrtPrice, 1 << 192)
                        + FullMath.mulDivRoundingUp(position.sqrtPrice, 1, 1 << 96))
            ) + 1;
            vm.assume(minLiquidity <= liquidityPool / minAmountIn);
            position.liquidity = uint128(bound(position.liquidity, minLiquidity, liquidityPool / minAmountIn));
        }
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Rebalancer is allowed as Asset Manager.
        allowRebalancerAsAssetManager();

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE));

        // And: The initiator charges no swap fee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = 0;

        // And: The new position has the ticks of the old one.
        initiatorParams.strategyData = abi.encode(position.tickLower, position.tickUpper);

        // And: A token0 balance of at least twice what the swap can leave unsold.
        initiatorParams.amountIn1 = 0;
        {
            (,,, uint256 lowerSqrtPriceDeviation,,) = rebalancer.accountInfo(address(account));
            uint256 lowerBoundSqrtPrice = FullMath.mulDiv(position.sqrtPrice, lowerSqrtPriceDeviation, 1e18);
            uint256 maxAmountIn = FullMath.mulDiv(
                FullMath.mulDiv(liquidityPool, position.sqrtPrice - lowerBoundSqrtPrice - 2, lowerBoundSqrtPrice),
                1 << 96,
                position.sqrtPrice
            );
            maxAmountIn = FixedPointMathLib.min(maxAmountIn, liquidityPool / position.liquidity);
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                FullMath.mulDiv(
                    SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtPriceAtTick(position.tickLower),
                            uint160(position.sqrtPrice),
                            position.liquidity,
                            false
                        ) / (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                        - FullMath.mulDivRoundingUp(position.sqrtPrice, 1, 1 << 96),
                    1 << 192,
                    position.sqrtPrice * position.sqrtPrice
                )
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn, FullMath.mulDiv(liquidityPool, 1 << 192, position.sqrtPrice * position.sqrtPrice)
            );
            vm.assume(minAmountIn <= maxAmountIn);
            initiatorParams.amountIn0 = uint128(bound(initiatorParams.amountIn0, minAmountIn, maxAmountIn));
        }

        // And: Nothing is withdrawn.
        initiatorParams.amountOut0 = 0;
        initiatorParams.amountOut1 = 0;

        // And: Account owns the position and the token0 balance.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(
            address(metadex03PositionManager), position, initiatorParams.amountIn0, initiatorParams.amountIn1
        );

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling rebalance.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: The new position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id + 1), address(account));

        // And: The Rebalancer holds no tokens.
        assertEq(token0.balanceOf(address(rebalancer)), 0);
        assertEq(token1.balanceOf(address(rebalancer)), 0);

        // And: The Account holds at most the unsold token0.
        assertLe(token0.balanceOf(address(account)), unsold);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_rebalance_StakedMetadexCLAM(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 rewards
    ) public {
        vm.assume(initiator != address(0));

        // Given: A valid staked position in range.
        (uint256 amount0, uint256 amount1) = setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        initiatorParams.oldId = uint96(position.id);

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));

        // And: Rebalancer is allowed as Asset Manager.
        allowRebalancerAsAssetManager();

        // And: Account info is set.
        setAccountInfo(initiator, bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE));

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

        // And: The withdrawn amount is smaller than the position balance.
        initiatorParams.amountOut0 =
            uint128(bound(initiatorParams.amountOut0, 0, (amount0 + initiatorParams.amountIn0) / 2));
        initiatorParams.amountOut1 =
            uint128(bound(initiatorParams.amountOut1, 0, (amount1 + initiatorParams.amountIn1) / 2));

        // And: Account owns the staked position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(stakedMetadex03CLAM), position, initiatorParams.amountIn0, initiatorParams.amountIn1);

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling rebalance.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: The new staked position is deposited back into the account.
        assertEq(ERC721(address(stakedMetadex03CLAM)).ownerOf(position.id + 1), address(account));

        // And: The account balances are correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }
}
