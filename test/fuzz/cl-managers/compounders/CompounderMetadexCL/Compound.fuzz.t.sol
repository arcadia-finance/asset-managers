/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { CompounderMetadexCL_Fuzz_Test } from "./_CompounderMetadexCL.fuzz.t.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "compound" of contract "CompounderSlipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(divide-before-multiply,erc20-unchecked-transfer,unsafe-typecast)
contract Compound_CompounderMetadexCL_Fuzz_Test is CompounderMetadexCL_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderMetadexCL_Fuzz_Test.setUp();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a pool with an in range position that carries both tokens.
    function setInRangePosition(uint128 liquidityPool, PositionState memory position, bool staked) internal {
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, staked);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
    }

    function allowCompounderAsAssetManager() internal {
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
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
    function testFuzz_Revert_compound_Paused(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Compounder is paused.
        vm.prank(users.owner);
        compounder.setPauseFlag(true);

        // When: Calling compound.
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        // Then: It reverts.
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_Reentered(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: Calling compound.
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        // Then: It reverts.
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidInitiator(
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Caller is not address(0).
        vm.assume(caller != address(0));

        // And: The owner of the account has not set an initiator yet.

        // When: Calling compound.
        vm.prank(caller);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        // Then: It reverts.
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Success_compound_MetadexCL(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Compounder is allowed as Asset Manager.
        allowCompounderAsAssetManager();

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(metadex03PositionManager), position, initiatorParams.amount0, initiatorParams.amount1);

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: Liquidity is not 0.
        {
            (uint256 balance0, uint256 balance1) = getFeeAmountsMetadex03CL(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.claimFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            vm.assume(rebalanceParams.amountIn > 1e8);
            vm.assume(rebalanceParams.minLiquidity > 1e8);
        }

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling compound.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);
    }

    function testFuzz_Success_compound_MetadexCL_PriceOnLowerTick(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
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
        position.liquidity = uint128(bound(position.liquidity, 1, liquidityPool));
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Compounder is allowed as Asset Manager.
        allowCompounderAsAssetManager();

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: The initiator charges no swap fee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = 0;

        // And: A token0 balance large enough for the minimum liquidity ratio.
        uint256 unsold = FullMath.mulDivRoundingUp((uint256(liquidityPool) + position.liquidity), 9, 1 << 99);
        unsold = ((position.sqrtPrice >> 145) + 5) * unsold + 2
            * FullMath.mulDivRoundingUp(position.sqrtPrice, 5 * position.sqrtPrice, 1 << 194) + 5;
        uint256 minAmountIn = 2 * unsold;
        {
            uint256 minAmount = (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                * (FullMath.mulDivRoundingUp(minAmountIn, 1 << 192, position.sqrtPrice * position.sqrtPrice)
                    + FullMath.mulDivRoundingUp(1, 1 << 96, position.sqrtPrice));
            uint256 maxAmount = SqrtPriceMath.getAmount0Delta(
                uint160(position.sqrtPrice),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                uint128(liquidityPool / minAmountIn),
                false
            );
            vm.assume(minAmount <= maxAmount);
            initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, minAmount, maxAmount));
        }

        // And: A token1 balance of at least twice what the swap can leave unsold.
        {
            (,, uint256 upperSqrtPriceDeviation,,) = compounder.accountInfo(address(account));
            uint256 maxAmountIn = FullMath.mulDiv(
                liquidityPool,
                FullMath.mulDiv(position.sqrtPrice, upperSqrtPriceDeviation, 1e18) - position.sqrtPrice - 2,
                1 << 96
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                liquidityPool
                    / LiquidityAmounts.getLiquidityForAmount0(
                        uint160(position.sqrtPrice),
                        TickMath.getSqrtPriceAtTick(position.tickUpper),
                        initiatorParams.amount0
                    )
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                FullMath.mulDiv(
                    initiatorParams.amount0 / (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                        - FullMath.mulDivRoundingUp(1, 1 << 96, position.sqrtPrice),
                    position.sqrtPrice * position.sqrtPrice,
                    1 << 192
                )
            );
            vm.assume(minAmountIn <= maxAmountIn);
            initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, minAmountIn, maxAmountIn));
        }

        // And: Account owns the position and the token balances.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(metadex03PositionManager), position, initiatorParams.amount0, initiatorParams.amount1);

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

        // When: Calling compound.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        {
            (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
            assertGt(liquidity, position.liquidity);
        }

        // And: The Compounder holds no tokens.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);

        // And: The Account holds at most the unsold token1.
        assertLe(token1.balanceOf(address(account)), unsold);
    }

    function testFuzz_Success_compound_MetadexCL_PriceOnUpperTick(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, false);

        // And: The pool reached its price from above.
        poolCl.setCurrentTick(position.tickCurrent - 1);

        // And: A position with its upper tick on the pool price.
        position.tickUpper = position.tickCurrent;
        position.tickLower = int24(
            bound(
                position.tickLower,
                BOUND_TICK_LOWER / position.tickSpacing,
                position.tickCurrent / position.tickSpacing - 1
            )
        ) * position.tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1, liquidityPool));
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Metadex CL is an allowed asset.
        deployMetadex03CLAM();

        // And: Compounder is allowed as Asset Manager.
        allowCompounderAsAssetManager();

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: The initiator charges no swap fee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = 0;

        // And: A token1 balance large enough for the minimum liquidity ratio.
        uint256 unsold = FixedPointMathLib.divUp(
            FullMath.mulDivRoundingUp((uint256(liquidityPool) + position.liquidity), 5 << 94, position.sqrtPrice),
            position.sqrtPrice
        );
        unsold = ((position.sqrtPrice >> 145) + 5) * unsold + 2
            * FullMath.mulDivRoundingUp(5 << 190, 1, position.sqrtPrice * position.sqrtPrice) + 5;
        uint256 minAmountIn = 2 * unsold;
        {
            uint256 minAmount = (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                * (FullMath.mulDivRoundingUp(minAmountIn, position.sqrtPrice * position.sqrtPrice, 1 << 192)
                    + FullMath.mulDivRoundingUp(position.sqrtPrice, 1, 1 << 96));
            uint256 maxAmount = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                uint160(position.sqrtPrice),
                uint128(liquidityPool / minAmountIn),
                false
            );
            vm.assume(minAmount <= maxAmount);
            initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, minAmount, maxAmount));
        }

        // And: A token0 balance of at least twice what the swap can leave unsold.
        {
            (,,, uint256 lowerSqrtPriceDeviation,) = compounder.accountInfo(address(account));
            uint256 lowerBoundSqrtPrice = FullMath.mulDiv(position.sqrtPrice, lowerSqrtPriceDeviation, 1e18);
            uint256 maxAmountIn = FullMath.mulDiv(
                FullMath.mulDiv(liquidityPool, position.sqrtPrice - lowerBoundSqrtPrice - 2, lowerBoundSqrtPrice),
                1 << 96,
                position.sqrtPrice
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                liquidityPool
                    / LiquidityAmounts.getLiquidityForAmount1(
                        TickMath.getSqrtPriceAtTick(position.tickLower),
                        uint160(position.sqrtPrice),
                        initiatorParams.amount1
                    )
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                FullMath.mulDiv(
                    initiatorParams.amount1 / (1e18 / (1e18 - MIN_LIQUIDITY_RATIO))
                        - FullMath.mulDivRoundingUp(position.sqrtPrice, 1, 1 << 96),
                    1 << 192,
                    position.sqrtPrice * position.sqrtPrice
                )
            );
            maxAmountIn = FixedPointMathLib.min(
                maxAmountIn,
                FullMath.mulDiv(
                    (uint256(liquidityPool) + position.liquidity), 1 << 192, position.sqrtPrice * position.sqrtPrice
                )
            );
            vm.assume(minAmountIn <= maxAmountIn);
            initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, minAmountIn, maxAmountIn));
        }

        // And: Account owns the position and the token balances.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(metadex03PositionManager), position, initiatorParams.amount0, initiatorParams.amount1);

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

        // When: Calling compound.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        {
            (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
            assertGt(liquidity, position.liquidity);
        }

        // And: The Compounder holds no tokens.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);

        // And: The Account holds at most the unsold token0.
        assertLe(token0.balanceOf(address(account)), unsold);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_compound_StakedMetadexCLAM(
        uint128 liquidityPool,
        uint24 initialFee,
        bool initialFeeEnabled,
        PositionState memory position,
        uint256 rewards,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        vm.assume(initiator != address(0));

        // Given: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        initiatorParams.id = uint96(position.id);

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Compounder is allowed as Asset Manager.
        allowCompounderAsAssetManager();

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));

        // And: Account owns the staked position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        depositInAccount(address(stakedMetadex03CLAM), position, initiatorParams.amount0, initiatorParams.amount1);

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: Liquidity is not 0.
        {
            vm.assume(uint256(initiatorParams.amount0) + initiatorParams.amount1 > 1e6);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                initiatorParams.amount0,
                initiatorParams.amount1
            );

            vm.assume(rebalanceParams.amountIn > 1e8);
            vm.assume(rebalanceParams.minLiquidity > 1e8);
        }

        // And: A new block in which the pool may charge another fee.
        if (initialFeeEnabled) {
            stdstore.target(address(metadex03CLFactory))
                .sig("tickSpacingToFee(int24)")
                .with_key(uint256(int256(position.tickSpacing)))
                .checked_write(bound(initialFee, 0, MAX_POOL_FEE));
        }
        vm.warp(vm.getBlockTimestamp() + 1);

        // When: Calling compound.
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position is deposited back into the account.
        assertEq(ERC721(address(stakedMetadex03CLAM)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);
    }
}
