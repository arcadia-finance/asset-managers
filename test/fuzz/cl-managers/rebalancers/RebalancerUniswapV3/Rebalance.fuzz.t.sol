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
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "RebalancerUniswapV3".
 */
// forge-lint: disable-next-item(divide-before-multiply,erc20-unchecked-transfer,unsafe-typecast)
contract Rebalance_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultRebalancerHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();

        strategyHook = new DefaultRebalancerHook();
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
        // Given: Account is not a precompile.
        account_ = address(uint160(bound(uint160(account_), 21, type(uint160).max)));

        // And: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not the console.
        vm.assume(account_ != address(0x000000000000000000636F6e736F6c652e6c6f67));

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(bytes(""));
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
        vm.warp(vm.getBlockTimestamp() + 10 minutes);
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

    function testFuzz_Success_rebalance(
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
        setPoolState(liquidityPool, position);
        givenValidPositionStateInRange(position);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        (uint256 amount0, uint256 amount1) = setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: uniV3 is allowed.
        deployUniswapV3AM();

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
        (tickLower, tickUpper) =
            givenValidTicks(tickLower, tickUpper, BOUND_TICK_LOWER, BOUND_TICK_UPPER, 10_000, position.tickSpacing);
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: position has fees.
        feeSeed = bound(feeSeed, 0, type(uint56).max);
        generateFees(feeSeed, feeSeed);

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
        // forge-lint: disable-start(erc20-unchecked-transfer)
        ERC721(address(nonfungiblePositionManager))
            .transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        // forge-lint: disable-end(erc20-unchecked-transfer)
        deal(address(token0), users.accountOwner, initiatorParams.amountIn0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amountIn1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(nonfungiblePositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amountIn0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amountIn1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amountIn0);
            token1.approve(address(account), initiatorParams.amountIn1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,,) = poolUniswap.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position.id + 1), address(account));

        // And: Account balances should be correct.
        assertGe(token0.balanceOf(address(account)), initiatorParams.amountOut0);
        assertGe(token1.balanceOf(address(account)), initiatorParams.amountOut1);
    }

    function testFuzz_Success_rebalance_PriceOnLowerTick(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        position.tickSpacing = uniswapV3Factory.feeAmountTickSpacing(position.poolFee);
        position.tickCurrent -= (position.tickCurrent % position.tickSpacing + position.tickSpacing)
            % position.tickSpacing;
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position);

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
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: uniV3 is allowed.
        deployUniswapV3AM();

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
        ERC721(address(nonfungiblePositionManager))
            .transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token1), users.accountOwner, initiatorParams.amountIn1, true);
        {
            address[] memory assets_ = new address[](2);
            uint256[] memory assetIds_ = new uint256[](2);
            uint256[] memory assetAmounts_ = new uint256[](2);

            assets_[0] = address(nonfungiblePositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token1);
            assetAmounts_[1] = initiatorParams.amountIn1;

            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), position.id);
            token1.approve(address(account), initiatorParams.amountIn1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position.id + 1), address(account));

        // And: The Rebalancer holds no tokens.
        assertEq(token0.balanceOf(address(rebalancer)), 0);
        assertEq(token1.balanceOf(address(rebalancer)), 0);

        // And: The Account holds at most the unsold token1.
        assertLe(token1.balanceOf(address(account)), unsold);
    }

    function testFuzz_Success_rebalance_PriceOnUpperTick(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        PositionState memory position,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        position.tickSpacing = uniswapV3Factory.feeAmountTickSpacing(position.poolFee);
        position.tickCurrent -= (position.tickCurrent % position.tickSpacing + position.tickSpacing)
            % position.tickSpacing;
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position);

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
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: uniV3 is allowed.
        deployUniswapV3AM();

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
        ERC721(address(nonfungiblePositionManager))
            .transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amountIn0, true);
        {
            address[] memory assets_ = new address[](2);
            uint256[] memory assetIds_ = new uint256[](2);
            uint256[] memory assetAmounts_ = new uint256[](2);

            assets_[0] = address(nonfungiblePositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amountIn0;

            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amountIn0);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position.id + 1), address(account));

        // And: The Rebalancer holds no tokens.
        assertEq(token0.balanceOf(address(rebalancer)), 0);
        assertEq(token1.balanceOf(address(rebalancer)), 0);

        // And: The Account holds at most the unsold token0.
        assertLe(token0.balanceOf(address(account)), unsold);
    }
}
