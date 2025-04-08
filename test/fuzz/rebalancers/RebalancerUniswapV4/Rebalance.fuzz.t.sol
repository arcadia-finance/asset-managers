/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { BitPackingLib } from "../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
import { PositionInfo } from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalanceOptimizationMath } from "../../../../src/rebalancers/libraries/RebalanceOptimizationMath.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { SwapMath } from "../../../utils/uniswap-v3/SwapMath.sol";
import { SwapParams } from "../../../../src/rebalancers/interfaces/IPoolManager.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "RebalancerUniswapV4".
 */
contract Rebalance_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /* ///////////////////////////////////////////////////////////////
                              HELPERS
    /////////////////////////////////////////////////////////////// */

    function moveTicksRightWithIncreasedTolerance(
        uint256 trustedSqrtPriceX96,
        address initiator,
        uint256 amount1ToSwap,
        bool maxRight
    ) public {
        (uint160 sqrtPriceX96, int24 tickCurrent,,) = stateView.getSlot0(v4PoolKey.toId());
        uint128 liquidity_ = stateView.getLiquidity(v4PoolKey.toId());

        (uint256 upperSqrtPriceDeviation,,,) = rebalancer.initiatorInfo(initiator);
        // Calculate max sqrtPriceX96 to the right to avoid unbalancedPool()
        uint256 sqrtPriceX96Target = trustedSqrtPriceX96.mulDivDown(upperSqrtPriceDeviation, 1e18);

        // Take 5 % below to allow swapping and avoid unbalancedPool
        sqrtPriceX96Target -= ((sqrtPriceX96Target * (0.05 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the max amount of token 1 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity_, amountRemaining, 100 * POOL_FEE
        );

        // Amount to swap should be max equal to amountIn which will achieve the highest possible swap withing maxTolerance.
        if (maxRight) {
            amount1ToSwap = amountIn;
        } else {
            amount1ToSwap = bound(amount1ToSwap, 1, amountIn);
        }

        vm.startPrank(users.swapper);
        deal(address(token1), users.swapper, type(uint128).max);

        // Encode the swap data.
        SwapParams memory params =
            SwapParams({ zeroForOne: false, amountSpecified: -int256(amount1ToSwap), sqrtPriceLimitX96: 0 });

        bytes memory swapData = abi.encode(params, v4PoolKey);

        // Do the swap.
        poolManager.unlock(swapData);

        vm.stopPrank();

        (, int24 tick,,) = stateView.getSlot0(v4PoolKey.toId());
        vm.assume(tick > tickCurrent);
    }

    function moveTicksLeftWithIncreasedTolerance(int24 initLpLowerTick, uint256 amount0ToSwap, bool maxLeft) public {
        (uint160 sqrtPriceX96, int24 tickCurrent,,) = stateView.getSlot0(v4PoolKey.toId());
        uint128 liquidity_ = stateView.getLiquidity(v4PoolKey.toId());

        // Calculate max sqrtPriceX96 to the left to avoid unbalancedPool()
        // No probleme in this case as lower ratio will be 0.
        // But we still want to be within initial lp range for liquidity
        uint256 sqrtPriceX96Target = TickMath.getSqrtPriceAtTick(initLpLowerTick);

        // Take 5 % above to ensure we are withing the liquidity and enable swapping without being unbalanced
        sqrtPriceX96Target += ((sqrtPriceX96Target * (0.05 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the max amount of token 0 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity_, amountRemaining, 100 * POOL_FEE
        );

        // Amount to swap should be max amountIn that will achieve the highest possible swap withing maxTolerance.
        if (maxLeft) {
            amount0ToSwap = amountIn;
        } else {
            amount0ToSwap = bound(amount0ToSwap, 1, amountIn);
        }

        vm.startPrank(users.swapper);
        deal(address(token0), users.swapper, type(uint128).max);

        // Encode the swap data.
        SwapParams memory params =
            SwapParams({ zeroForOne: true, amountSpecified: -int256(amount0ToSwap), sqrtPriceLimitX96: 0 });

        bytes memory swapData = abi.encode(params, v4PoolKey);

        // Do the swap.
        poolManager.unlock(swapData);

        vm.stopPrank();

        (, int24 tick,,) = stateView.getSlot0(v4PoolKey.toId());
        vm.assume(tick < tickCurrent);
    }

    function getRebalanceParams(
        uint256 tokenId,
        int24 lpLowerTick,
        int24 lpUpperTick,
        RebalancerUniswapV4.PositionState memory position,
        address initiator
    )
        public
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            bool zeroToOne,
            uint256 amountIn,
            uint256 amountOut,
            uint256 amountInitiatorFee
        )
    {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPriceX96),
            TickMath.getSqrtPriceAtTick(lpLowerTick),
            TickMath.getSqrtPriceAtTick(lpUpperTick),
            position.liquidity
        );

        {
            (uint256 fee0, uint256 fee1) =
                getFeeAmounts(tokenId, v4PoolKey.toId(), lpLowerTick, lpUpperTick, position.liquidity);
            amount0 += fee0;
            amount1 += fee1;
        }

        (,, uint256 initiatorFee,) = rebalancer.initiatorInfo(initiator);

        (, zeroToOne, amountInitiatorFee, amountIn, amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        address positionManager,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper,
        uint256 trustedSqrtPriceX96
    ) public {
        vm.assume(account_ != address(0));
        // Given : account is not address(0)
        rebalancer.setAccount(account_);

        // When : calling rebalance
        // Then : it should revert
        vm.expectRevert(RebalancerUniswapV4.Reentered.selector);
        rebalancer.rebalance(account_, positionManager, tokenId, trustedSqrtPriceX96, tickLower, tickUpper, "");
    }

    function testFuzz_Revert_rebalancePosition_InitiatorNotValid(
        uint256 tokenId,
        address positionManager,
        int24 tickLower,
        int24 tickUpper,
        uint256 trustedSqrtPriceX96
    ) public {
        // Given : Owner of the account has not set an initiator yet
        // When : calling rebalance
        // Then : it should revert
        vm.expectRevert(RebalancerUniswapV4.InitiatorNotValid.selector);
        rebalancer.rebalance(address(account), positionManager, tokenId, trustedSqrtPriceX96, tickLower, tickUpper, "");
    }

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(tokenId))
            );
            position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);
        }

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - MIN_TICK_SPACING));
        tickUpper = int24(bound(tickUpper, tickCurrent + MIN_TICK_SPACING, BOUND_TICK_UPPER));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        vm.expectEmit();
        emit RebalancerUniswapV4.Rebalance(address(account), address(positionManagerV4), tokenId, tokenId + 1);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        assertEq(tickLower, info.tickLower());
        assertEq(tickUpper, info.tickUpper());
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token0(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move upper tick to the right (should trigger a oneToZero swap)
        tickLower = position.tickLower;
        tickUpper = int24(bound(tickUpper, position.tickUpper + 1, BOUND_TICK_UPPER));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                tokenId, tickLower, tickUpper, TickMath.getSqrtPriceAtTick(tickCurrent), initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, position.tickLower, position.tickUpper, position_, initiator);
            vm.assume(zeroToOne == false);
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(token1.balanceOf(initiator), 0);
        assertLe(token1.balanceOf(initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token1(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move lower tick to the left (should trigger a zeroToOne swap)
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickLower - 1000));
        tickUpper = position.tickUpper;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                tokenId, tickLower, tickUpper, TickMath.getSqrtPriceAtTick(tickCurrent), initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, position.tickLower, position.tickUpper, position_, initiator);
            vm.assume(zeroToOne == true);
            // And : Assume minimum amountIn so that there's a positive fee.
            vm.assume(amountIn > 1e6);
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(token0.balanceOf(initiator), 0);
        assertLe(token0.balanceOf(initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_BalancedWithSameTickSpacing(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 newTick,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move current tick to the right.
        newTick = int24(bound(newTick, tickCurrent + 10, position.tickUpper));
        poolManager.setCurrentPrice(v4PoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 trustedSqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account), address(positionManagerV4), tokenId, uint256(trustedSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return the correct values
        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = TICK_SPACING;
            int24 tickRange = position.tickUpper - position.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = newTick - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        // There can be 1 tick difference due to roundings.
        assertEq(tickLowerExpected, info.tickLower());
        assertEq(tickUpperExpected, info.tickUpper());
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_BalancedWithSameTickSpacing(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 newTick,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move current tick to the left.
        newTick = int24(bound(newTick, position.tickLower, tickCurrent - 10));
        poolManager.setCurrentPrice(v4PoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account.
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 trustedSqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account), address(positionManagerV4), tokenId, uint256(trustedSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return the correct values
        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = TICK_SPACING;
            int24 tickRange = position.tickUpper - position.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = newTick - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        // There can be 1 tick difference due to roundings.
        assertEq(tickLowerExpected, info.tickLower());
        assertEq(tickUpperExpected, info.tickUpper());
    }

    /* ///////////////////////////////////////////////////////////////
                            NATIVE ETH FLOW
    /////////////////////////////////////////////////////////////// */

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks_nativeETH(
        uint256 fee,
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));
        int24 tickSpacing = TICK_SPACING;

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - MIN_TICK_SPACING));
        tickUpper = int24(bound(tickUpper, tickCurrent + MIN_TICK_SPACING, BOUND_TICK_UPPER));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        vm.expectEmit();
        emit RebalancerUniswapV4.Rebalance(address(account), address(positionManagerV4), tokenId, tokenId + 1);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        assertEq(tickLower, info.tickLower());
        assertEq(tickUpper, info.tickUpper());
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token0_NativeETH(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER - 100));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move upper tick to the right (should trigger a oneToZero swap)
        tickLower = position.tickLower;
        tickUpper = int24(bound(tickUpper, position.tickUpper + 1, BOUND_TICK_UPPER));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        address initiatorStack = initiator;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                tokenId, tickLower, tickUpper, TickMath.getSqrtPriceAtTick(tickCurrent), initiatorStack
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, position.tickLower, position.tickUpper, position_, initiatorStack);
            vm.assume(zeroToOne == false);
            // And : Assume minimum amountIn to generate fees.
            vm.assume(amountIn > 1e6);
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(token1.balanceOf(initiator), 0);
        assertLe(token1.balanceOf(initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token1_NativeETH(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER + 100, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e11, 1e18));

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move lower tick to the left (should trigger a zeroToOne swap)
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, position.tickLower - 10));
        tickUpper = position.tickUpper;

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                tokenId, tickLower, tickUpper, TickMath.getSqrtPriceAtTick(tickCurrent), initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, position.tickLower, position.tickUpper, position_, initiator);
            vm.assume(zeroToOne == true);
            // And : Assume minimum amountIn so that there's a positive fee.
            vm.assume(amountIn > 1e6);
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(initiator.balance, 0);
        assertLe(initiator.balance, expectedFee);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_BalancedWithSameTickSpacing_NativeETH(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 newTick,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e14, 1e18));

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move current tick to the right.
        newTick = int24(bound(newTick, tickCurrent + 10, position.tickUpper));
        poolManager.setCurrentPrice(nativeEthPoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 trustedSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account), address(positionManagerV4), tokenId, uint256(trustedSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return the correct values
        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = TICK_SPACING;
            int24 tickRange = position.tickUpper - position.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = newTick - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        // There can be 1 tick difference due to roundings.
        assertEq(tickLowerExpected, info.tickLower());
        assertEq(tickUpperExpected, info.tickUpper());
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_BalancedWithSameTickSpacing_NativeETH(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 newTick,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e14, 1e18));

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move current tick to the left.
        newTick = int24(bound(newTick, position.tickLower, tickCurrent - 10));
        poolManager.setCurrentPrice(nativeEthPoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));

        // And: The initiator is initiated.
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, MIN_INITIATOR_FEE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account.
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint160 trustedSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account), address(positionManagerV4), tokenId, uint256(trustedSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return the correct values
        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = TICK_SPACING;
            int24 tickRange = position.tickUpper - position.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = newTick - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        // Then : It should return the correct values
        (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId + 1);

        // There can be 1 tick difference due to roundings.
        assertEq(tickLowerExpected, info.tickLower());
        assertEq(tickUpperExpected, info.tickUpper());
    }

    function testFuzz_Success_rebalancePosition_NativeETH_SurplusInWethReceivedByAccount(
        uint256 fee,
        uint128 liquidityPool,
        uint256 tolerance,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        RebalancerUniswapV4.PositionState memory position,
        address account_
    ) public {
        // Given: rebalancer is not the account.
        vm.assume(account_ != address(rebalancer));

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: Deploy V4 AM and native ETH pool.
        deployNativeAM();
        (, position.sqrtPriceX96) = deployNativeEthPool(liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.startPrank(registry.owner());
            erc20AM.addAsset(WETH, BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = tickCurrent - 100;
        position.tickLower = position.tickLower / TICK_SPACING * TICK_SPACING;
        position.tickUpper = tickCurrent + 100;
        position.tickUpper = position.tickUpper / TICK_SPACING * TICK_SPACING;
        position.liquidity = 1e20;

        uint256 tokenId = mintPositionV4(
            nativeEthPoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And : Move lower tick to the left (should trigger a zeroToOne swap)
        tickLower = position.tickLower - 100;
        tickUpper = position.tickUpper;

        // And: The initiator is initiated.
        tolerance = MAX_TOLERANCE;
        fee = MIN_INITIATOR_FEE;
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                tokenId, tickLower, tickUpper, TickMath.getSqrtPriceAtTick(tickCurrent), initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,,) =
                getRebalanceParams(tokenId, position.tickLower, position.tickUpper, position_, initiator);
            vm.assume(zeroToOne == true);
            // And : Assume minimum amountIn so that there's a positive fee.
            vm.assume(amountIn > 1e6);
        }

        (uint160 currentSqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());

        // When : calling rebalance()
        vm.prank(initiator);
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(ERC20(WETH).balanceOf(address(account)), 0);
    }
}
