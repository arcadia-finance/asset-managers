/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
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

    function moveTicksLeftWithIncreasedTolerance(
        uint256 trustedSqrtPriceX96,
        int24 initLpLowerTick,
        uint256 amount0ToSwap,
        bool maxLeft
    ) public {
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

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks_1(
        RebalancerUniswapV4.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given : Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And : Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        initPoolAndAddLiquidity(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE, TICK_SPACING, address(0));

        // And: A valid position with multiple tickSpacing.
        // And: Position is in range (has both tokens).
        int24 tickSpacing = TICK_SPACING;
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, tickCurrent - 10));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, tickCurrent + 10, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, 1e10));

        uint256 tokenId = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            address(users.liquidityProvider)
        );

        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(tokenId))
        );
        position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

        // And: A new position with a valid tick range.
        // And: New Position is below current tick.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, tickCurrent - 2));
        tickLower = tickLower / tickSpacing * tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 1, tickCurrent - 1));
        tickUpper = tickUpper / tickSpacing * tickSpacing;

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

        (uint128 mintedLiquidity,,) =
            stateView.getPositionInfo(v4PoolKey.toId(), address(account), tickLower, tickUpper, bytes32(tokenId + 1));

        emit log_named_uint("mintedLiquidity", mintedLiquidity);

        /*         // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual, uint256 liquidity,,,,) =
            positionManagerV4.positions(tokenId + 1);

        (, tickCurrent,,) = stateView.getSlot0(v4PoolKey.slot0());

        // There can be 1 tick difference due to roundings.
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual); */
    }

    /*     function testFuzz_Success_rebalancePosition_SamePriceNewTicks_1(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        FeeGrowth memory feeData,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars, feeData);

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, lpVars.tickLower - ((INIT_LP_TICK_RANGE / 2) - 100), lpVars.tickLower - 1));
        tickUpper = int24(bound(tickUpper, lpVars.tickUpper + 1, lpVars.tickUpper + ((INIT_LP_TICK_RANGE / 2) - 100)));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

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
        vm.prank(initVars.initiator);
        vm.expectEmit();
        emit RebalancerUniswapV4.Rebalance(
            address(account), address(positionManagerV4), tokenId, tokenId + 1
        );
        rebalancer.rebalance(
            address(account),
            address(positionManagerV4),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        (uint128 mintedLiquidity,,) = stateView.getPositionInfo(v4PoolKey.toId(), address(account), tickLower, tickUpper, bytes32(tokenId + 1));

        emit log_named_uint("mintedLiquidity", mintedLiquidity);

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual, uint256 liquidity,,,,) =
            positionManagerV4.positions(tokenId + 1);

        (, int24 tickCurrent,,) = stateView.getSlot0(v4PoolKey.slot0());

        // There can be 1 tick difference due to roundings.
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual); 

    } 

    /*     function testFuzz_Success_rebalancePosition_InitiatorFees_Token0(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickUpper
    ) public {
        // Given: Initiator is not the liquidity provider.
        vm.assume(initVars.initiator != users.liquidityProvider);

        // And: Initiator is not the account.
        vm.assume(initVars.initiator != address(account));

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Move upper tick to the right (should trigger a oneToZero swap)
        int24 tickLower = lpVars.tickLower;
        tickUpper = int24(bound(tickUpper, lpVars.tickUpper + 10, lpVars.tickUpper + ((INIT_LP_TICK_RANGE / 2) - 100)));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
            vm.assume(zeroToOne == false);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance()
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(token1.balanceOf(initVars.initiator), 0);
        assertLe(token1.balanceOf(initVars.initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token1(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower
    ) public {
        // Given: Initiator is not the liquidity provider.
        vm.assume(initVars.initiator != users.liquidityProvider);

        // And: Initiator is not the account.
        vm.assume(initVars.initiator != address(account));

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Move lower tick to the left (should trigger a zeroToOne swap)
        tickLower = int24(bound(tickLower, lpVars.tickLower - ((INIT_LP_TICK_RANGE / 2) - 100), lpVars.tickLower - 10));
        int24 tickUpper = lpVars.tickUpper;

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        uint256 expectedFee;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
            vm.assume(zeroToOne == true);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance()
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        assertGt(token0.balanceOf(initVars.initiator), 0);
        assertLe(token0.balanceOf(initVars.initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount1ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 0.9 * 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // Move ticks right (by maxTolerance in this case 1e18 = 100%)
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, false);

        (uint160 currentSqrtPriceX96, int24 tickBeforeRebalance,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance() with 0 value for lower and upper ticks
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account), address(nonfungiblePositionManager), tokenId, uint256(currentSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = uniV3Pool.tickSpacing();
            int24 tickRange = lpVars.tickUpper - lpVars.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = tickBeforeRebalance - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickUpperExpected, tickUpper);
        assertEq(tickLowerExpected, tickLower);
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount0ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 0.9 * 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // Move ticks left
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, false);

        (uint160 currentSqrtPriceX96, int24 tickBeforeRebalance,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance() with 0 value for lower and upper ticks
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account), address(nonfungiblePositionManager), tokenId, uint256(currentSqrtPriceX96), 0, 0, ""
        );

        // Then : It should return correct values
        int24 tickLowerExpected;
        int24 tickUpperExpected;
        {
            int24 tickSpacing = uniV3Pool.tickSpacing();
            int24 tickRange = lpVars.tickUpper - lpVars.tickLower;
            int24 rangeBelow = tickRange / (2 * tickSpacing) / tickSpacing;
            tickLowerExpected = tickBeforeRebalance - rangeBelow;
            tickUpperExpected = tickLowerExpected + tickRange;
        }
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickUpperExpected, tickUpper);
        assertEq(tickLowerExpected, tickLower);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_CustomTicks(
        uint256 amount1ToSwap,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        InitVariables memory initVars
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        {
            uint256 maxTolerance = 0.8 * 1e18;
            deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);
        }

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // Ticks have moved to the right
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, false);

        uint256 amount0;
        uint256 amount1;
        uint160 sqrtPrice;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );

            uint256 amountIn;
            uint256 amountOut;
            bool zeroToOne;
            {
                uint256 amountInitiatorFee;
                (amount0, amount1, zeroToOne, amountIn, amountOut, amountInitiatorFee) =
                    getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
                // Initiator fee should be greater than one to at least compensate for rounding errors.
                vm.assume(amountInitiatorFee > 0);
            }

            // Exclude edge case where sqrtPrice starts in range, but sqrtPriceNew goes out of range during calculations.
            (sqrtPrice,,,,,,) = uniV3Pool.slot0();
            if (
                TickMath.getSqrtPriceAtTick(tickLower) < sqrtPrice && sqrtPrice < TickMath.getSqrtPriceAtTick(tickUpper)
            ) {
                sqrtPrice = RebalanceOptimizationMath._approximateSqrtPriceNew(
                    zeroToOne, position_.fee, uniV3Pool.liquidity(), sqrtPrice, amountIn, amountOut
                );
                vm.assume(
                    TickMath.getSqrtPriceAtTick(tickLower) < sqrtPrice - 100
                        && sqrtPrice + 100 < TickMath.getSqrtPriceAtTick(tickUpper)
                );
            }

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            (amountOut, sqrtPrice,,) = quoter.quoteExactInputSingle(params);

            if (zeroToOne) {
                amount0 -= amountIn;
                amount1 += amountOut;
            } else {
                amount0 += amountOut;
                amount1 -= amountIn;
            }

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(position_.tickLower),
                TickMath.getSqrtPriceAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            vm.assume(liquidity > 0);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance()
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual);
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_CustomTicks(
        uint256 amount0ToSwap,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        InitVariables memory initVars
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        {
            uint256 maxTolerance = 0.9 * 1e18;
            deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);
        }

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // Ticks have moved to the right
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, false);

        uint256 amount0;
        uint256 amount1;
        uint160 sqrtPrice;
        {
            // Assume that liquidity will be bigger than 0
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );

            uint256 amountIn;
            uint256 amountOut;
            bool zeroToOne;
            {
                uint256 amountInitiatorFee;
                (amount0, amount1, zeroToOne, amountIn, amountOut, amountInitiatorFee) =
                    getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
                // Initiator fee should be greater than one to at least compensate for rounding errors.
                vm.assume(amountInitiatorFee > 0);
            }

            // Exclude edge case where sqrtPrice starts in range, but sqrtPriceNew goes out of range during calculations.
            (sqrtPrice,,,,,,) = uniV3Pool.slot0();
            if (
                TickMath.getSqrtPriceAtTick(tickLower) < sqrtPrice && sqrtPrice < TickMath.getSqrtPriceAtTick(tickUpper)
            ) {
                sqrtPrice = RebalanceOptimizationMath._approximateSqrtPriceNew(
                    zeroToOne, position_.fee, uniV3Pool.liquidity(), sqrtPrice, amountIn, amountOut
                );
                vm.assume(
                    TickMath.getSqrtPriceAtTick(tickLower) < sqrtPrice - 100
                        && sqrtPrice + 100 < TickMath.getSqrtPriceAtTick(tickUpper)
                );
            }

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            (amountOut, sqrtPrice,,) = quoter.quoteExactInputSingle(params);

            if (zeroToOne) {
                amount0 -= amountIn;
                amount1 += amountOut;
            } else {
                amount0 += amountOut;
                amount1 -= amountIn;
            }

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPrice,
                TickMath.getSqrtPriceAtTick(position_.tickLower),
                TickMath.getSqrtPriceAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            vm.assume(liquidity > 0);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance()
        vm.prank(initVars.initiator);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLower,
            tickUpper,
            ""
        );

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual);
    }

    function testFuzz_Success_rebalancePosition_ArbitrarySwap_ZeroToOne(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount1ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 0.9 * 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Move ticks to max right to ensure zeroToOne swap
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, true);

        // Avoid stack too deep
        address initiatorStack = initVars.initiator;
        LpVariables memory lpVarsStack = lpVars;

        uint256 amountIn;
        uint256 amountOut;
        {
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager),
                tokenId,
                lpVarsStack.tickLower,
                lpVarsStack.tickUpper,
                initiatorStack
            );

            uint256 amount0;
            uint256 amount1;
            bool zeroToOne;
            (amount0, amount1, zeroToOne, amountIn, amountOut,) =
                getRebalanceParams(tokenId, lpVarsStack.tickLower, lpVarsStack.tickUpper, position_, initiatorStack);

            // And : Should be a zeroToOneSwap
            vm.assume(zeroToOne == true);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            uint160 sqrtPriceNew;
            (amountOut, sqrtPriceNew,,) = quoter.quoteExactInputSingle(params);

            amount0 -= amountIn;
            amount1 += amountOut;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceNew,
                TickMath.getSqrtPriceAtTick(position_.tickLower),
                TickMath.getSqrtPriceAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            // And : Liquidity should be > 0
            vm.assume(liquidity > 0);
        }

        bytes memory swapData;
        {
            // Send token1 (amountOut) to router for swap
            deal(address(token1), address(routerMock), type(uint128).max);

            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), amountIn, amountOut);
            swapData = abi.encode(address(routerMock), amountIn, routerData);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : Calling rebalance()
        // Then : It should process an Arbitrary swap.
        vm.prank(initVars.initiator);
        vm.expectEmit();
        emit RouterMock.ArbitrarySwap(true);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            lpVarsStack.tickLower,
            lpVarsStack.tickUpper,
            swapData
        );
    }

    function testFuzz_Success_rebalancePosition_ArbitrarySwap_OneToZero(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 0.9 * 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initVars.initiator, address(0));

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Move ticks left to enable oneToZero swap
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, true);

        uint256 amount0;
        uint256 amount1;
        uint256 amountIn;
        uint256 amountOut;
        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));
        // Avoid stack too deep
        address initiatorStack = initVars.initiator;
        {
            // Assume that liquidity will be bigger than 0
            RebalancerUniswapV4.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initiatorStack
            );

            bool zeroToOne;
            (amount0, amount1, zeroToOne, amountIn, amountOut,) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initiatorStack);

            // And : We want to test for a oneToZero swap
            vm.assume(zeroToOne == false);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            uint160 sqrtPriceNew;
            (amountOut, sqrtPriceNew,,) = quoter.quoteExactInputSingle(params);

            amount0 += amountOut;
            amount1 -= amountIn;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceNew,
                TickMath.getSqrtPriceAtTick(position_.tickLower),
                TickMath.getSqrtPriceAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            // And : Liquidity minted should be bigger than zero
            vm.assume(liquidity > 0);
        }

        int24 tickLowerStack = tickLower;
        int24 tickUpperStack = tickUpper;
        bytes memory swapData;
        {
            // Send token0 (amountOut) to router for swap
            deal(address(token0), address(routerMock), type(uint128).max);

            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), amountIn, amountOut);
            swapData = abi.encode(address(routerMock), amountIn, routerData);
        }

        (uint160 currentSqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        // When : calling rebalance()
        // Then : It should process to an arbitrary swap
        vm.prank(initiatorStack);
        vm.expectEmit();
        emit RouterMock.ArbitrarySwap(true);
        rebalancer.rebalance(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            uint256(currentSqrtPriceX96),
            tickLowerStack,
            tickUpperStack,
            swapData
        );
    } */
}
