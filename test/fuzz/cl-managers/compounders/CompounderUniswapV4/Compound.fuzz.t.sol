/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { CompounderUniswapV4_Fuzz_Test } from "./_CompounderUniswapV4.fuzz.t.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solady/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { IWETH } from "../../../../../src/cl-managers/interfaces/IWETH.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import {
    ProtocolFeeLibrary
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/ProtocolFeeLibrary.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import {
    SqrtPriceMath
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { Vm } from "../../../../../lib/accounts-v2/lib/forge-std/src/Vm.sol";

/**
 * @notice Fuzz tests for the function "compound" of contract "CompounderUniswapV4".
 */
// forge-lint: disable-next-item(divide-before-multiply,erc20-unchecked-transfer,unsafe-typecast)
contract Rebalance_CompounderUniswapV4_Fuzz_Test is CompounderUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compound_Paused(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Compounder is Paused.
        vm.prank(users.owner);
        compounder.setPauseFlag(true);

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_Reentered(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidAccount(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
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

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(bytes(""));
        } else {
            vm.expectRevert(bytes(""));
        }
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidInitiator(
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Revert_compound_ChangeAccountOwnership(
        Compounder.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Compounder is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Compounder is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        vm.warp(vm.getBlockTimestamp() + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = 0;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling compound
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Success_compound_NotNative(
        uint128 liquidityPool,
        uint24 protocolFee,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        (, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, protocolFee, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Position has fees.
        feeSeed = bound(feeSeed, type(uint8).max, type(uint48).max);
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: liquidity is not 0.
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmountsV4(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                getAmmFee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            // Amounts should be big enough or rounding errors become too big.
            vm.assume(rebalanceParams.amountIn > 1e8);
            vm.assume(rebalanceParams.minLiquidity > 1e8);
        }

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        assertGt(positionManagerV4.getPositionLiquidity(position.id), position.liquidity);
    }

    function testFuzz_Success_compound_NotNative_PriceOnLowerTick(
        uint128 liquidityPool,
        uint24 protocolFee,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        (liquidityPool, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, protocolFee, false);

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
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(compounder);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

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
        uint256 minAmountIn = FullMath.mulDivRoundingUp(2 * unsold + 2, 899, 897);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.recordLogs();
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        assertGt(positionManagerV4.getPositionLiquidity(position.id), position.liquidity);

        // And: The Compounder holds no tokens.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);

        // And: The swap leaves at most the unsold token1.
        {
            (, int128 amount1,) = getSwap(vm.getRecordedLogs());
            assertLe(initiatorParams.amount1 - uint128(-amount1), unsold + initiatorParams.amount1 / 899 + 1);
        }
    }

    function testFuzz_Success_compound_NotNative_PriceOnUpperTick(
        uint128 liquidityPool,
        uint24 protocolFee,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with its price on a tick.
        (liquidityPool, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, protocolFee, false);

        // And: The pool reached its price from above.
        poolManager.setCurrentPrice(poolKey.toId(), position.tickCurrent - 1, uint160(position.sqrtPrice));

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
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(compounder);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

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
        uint256 minAmountIn = FullMath.mulDivRoundingUp(2 * unsold + 2, 899, 897);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.recordLogs();
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        assertGt(positionManagerV4.getPositionLiquidity(position.id), position.liquidity);

        // And: The Compounder holds no tokens.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);

        // And: The swap leaves at most the unsold token0.
        {
            (int128 amount0,,) = getSwap(vm.getRecordedLogs());
            assertLe(initiatorParams.amount0 - uint128(-amount0), unsold + initiatorParams.amount0 / 899 + 1);
        }
    }

    function testFuzz_Success_compound_NotNative_PositiveDelta(
        uint128 liquidityPool,
        uint24 protocolFee,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A pool with a non-zero lpFee and its price on a tick.
        (liquidityPool, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);
        position.poolFee = uint24(bound(position.poolFee, 1, MAX_POOL_FEE));
        position.sqrtPrice = TickMath.getSqrtPriceAtTick(position.tickCurrent);
        setPoolState(liquidityPool, position, protocolFee, false);

        // And: The pool reached its price from above.
        poolManager.setCurrentPrice(poolKey.toId(), position.tickCurrent - 1, uint160(position.sqrtPrice));

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: A position from below the balanced range up to the pool price.
        uint256 minSqrtPrice;
        {
            (,,, uint256 lowerSqrtPriceDeviation,) = compounder.accountInfo(address(account));
            minSqrtPrice = FullMath.mulDiv(position.sqrtPrice, lowerSqrtPriceDeviation, 1e18) + 1;
        }
        position.tickUpper = position.tickCurrent;
        position.tickLower = int24(
            bound(position.tickLower, BOUND_TICK_LOWER, TickMath.getTickAtSqrtPrice(uint160(minSqrtPrice)) - 1)
        );
        position.liquidity = uint128(bound(position.liquidity, 1, liquidityPool));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(compounder);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        }

        // And: The initiator charges no swap fee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = 0;

        // And: A token0 balance whose swap pays the position at least two wei of lp fee.
        {
            uint256 liquidityActive = stateView.getLiquidity(poolKey.toId());
            uint256 minAmount0;
            {
                (,,, uint24 lpFee) = stateView.getSlot0(poolKey.toId());
                uint256 protocolFee0 = ProtocolFeeLibrary.getZeroForOneFee(protocolFee);
                uint256 ammFee0 = ProtocolFeeLibrary.calculateSwapFee(uint16(protocolFee0), lpFee);
                minAmount0 = FullMath.mulDivRoundingUp(
                    8 * liquidityActive, 1e6 - ammFee0, position.liquidity * (ammFee0 - protocolFee0)
                ) + 1;
            }
            minAmount0 = FixedPointMathLib.max(
                minAmount0,
                FullMath.mulDivRoundingUp(8 * liquidityActive, 1 << 96, position.sqrtPrice * position.sqrtPrice)
            );
            uint256 maxAmount0 = FullMath.mulDiv(
                liquidityActive, minSqrtPrice - TickMath.getSqrtPriceAtTick(position.tickLower), position.sqrtPrice
            );
            maxAmount0 = FixedPointMathLib.sqrt(FullMath.mulDiv(maxAmount0, 1 << 96, 8 * position.sqrtPrice));
            maxAmount0 = FixedPointMathLib.min(
                maxAmount0,
                SqrtPriceMath.getAmount0Delta(
                    uint160(minSqrtPrice), uint160(position.sqrtPrice), uint128(liquidityActive), false
                )
            );
            vm.assume(minAmount0 <= maxAmount0);
            initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, minAmount0, maxAmount0));
        }

        // And: A token1 balance that needs at most one wei of token0.
        {
            uint256 liquidityActive = stateView.getLiquidity(poolKey.toId());
            uint256 maxAmount1 = SqrtPriceMath.getAmount1Delta(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                uint160(minSqrtPrice),
                uint128(liquidityActive / (2 * initiatorParams.amount0)),
                false
            );
            maxAmount1 = FixedPointMathLib.zeroFloorSub(
                maxAmount1,
                FullMath.mulDivRoundingUp(initiatorParams.amount0, position.sqrtPrice * position.sqrtPrice, 1 << 192)
            );
            uint256 minAmount1 = FullMath.mulDivRoundingUp(liquidityActive, 3, 1 << 96)
                + FullMath.mulDivRoundingUp(4, position.sqrtPrice * position.sqrtPrice, 1 << 192)
                + FullMath.mulDivRoundingUp(position.sqrtPrice, 1, 1 << 96) + 1;
            minAmount1 *= 1e18 / (1e18 - MIN_LIQUIDITY_RATIO);
            vm.assume(minAmount1 <= maxAmount1);
            initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, minAmount1, maxAmount1));
        }

        // And: Account owns the position and the token balances.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.recordLogs();
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        assertGt(positionManagerV4.getPositionLiquidity(position.id), position.liquidity);

        // And: The Compounder holds no tokens.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);

        // And: The PoolManager paid the positive token0 delta to the Compounder.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 amount0Paid;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(token0) && logs[i].topics.length == 3
                    && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")
                    && logs[i].topics[1] == bytes32(uint256(uint160(address(poolManager))))
                    && logs[i].topics[2] == bytes32(uint256(uint160(address(compounder))))
            ) amount0Paid += abi.decode(logs[i].data, (uint256));
        }
        assertGt(amount0Paid, 0);
    }

    function testFuzz_Success_compound_IsNative(
        uint128 liquidityPool,
        uint24 protocolFee,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        (, protocolFee) = givenValidPoolState(liquidityPool, position, protocolFee);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, protocolFee, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Position has fees.
        feeSeed = bound(feeSeed, type(uint8).max, type(uint48).max);
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        vm.deal(users.accountOwner, initiatorParams.amount0);
        vm.prank(users.accountOwner);
        // forge-lint: disable-next-item(arbitrary-send-eth)
        IWETH(address(weth9)).deposit{ value: initiatorParams.amount0 }();
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(weth9);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            ERC20(address(weth9)).approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: liquidity is not 0.
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmountsV4(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                getAmmFee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            // Amounts should be big enough or rounding errors become too big.
            vm.assume(rebalanceParams.amountIn > 1e8);
            vm.assume(rebalanceParams.minLiquidity > 1e8);
        }

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));

        // And: The liquidity of the position increased.
        assertGt(positionManagerV4.getPositionLiquidity(position.id), position.liquidity);

        // And: The PositionManager holds no ETH.
        assertEq(address(positionManagerV4).balance, 0);
    }
}
