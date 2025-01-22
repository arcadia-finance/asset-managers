/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { RebalancerSpot } from "../../../../src/rebalancers/RebalancerSpot.sol";
import { RebalancerSpot_Fuzz_Test } from "./_RebalancerSpot.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { TwapLogic } from "../../../../src/libraries/TwapLogic.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "RebalancerSpot".
 */
contract GetPositionState_RebalancerSpot_Fuzz_Test is RebalancerSpot_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerSpot_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_UniswapV3_SameTickRange_OneTickSpacing(
        RebalancerSpot.PositionState memory position,
        uint128 liquidityPool,
        int24 tick,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 10 (fee = 500).
        uint24 POOL_FEE_ = 500;
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_);
        int24 tickSpacing = poolUniswap.tickSpacing();
        require(tickSpacing == 10);

        // And: A valid position with one tickSpacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = position.tickLower + tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancerSpot.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // And: The minimum time interval to calculate TWAT should have passed.
        vm.warp(block.timestamp + TwapLogic.TWAT_INTERVAL);

        // When: Calling getPositionState().
        RebalancerSpot.PositionState memory position_ =
            rebalancerSpot.getPositionState(address(nonfungiblePositionManager), id, tick, tick, initiator);

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, poolUniswap.tickSpacing());
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)) / tickSpacing * tickSpacing;
        assertEq(position_.tickLower, tickCurrent);
        assertEq(position_.tickUpper, position_.tickLower + tickSpacing);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);

        int24 twat = TwapLogic._getTwat(position_.pool);
        uint256 twaSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twat);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancerSpot.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, twaSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, twaSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV3_SameTickRange_MultipleTickSpacings(
        RebalancerSpot.PositionState memory position,
        uint128 liquidityPool,
        int24 tick,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // And: A pool with liquidity with tickSpacing 10 (fee = 500).
        uint24 POOL_FEE_ = 500;
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_);
        int24 tickSpacing = poolUniswap.tickSpacing();
        require(tickSpacing == 10);

        // And: A valid position with multiple tickSpacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
        (uint256 id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancerSpot.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // And: The minimum time interval to calculate TWAT should have passed.
        vm.warp(block.timestamp + TwapLogic.TWAT_INTERVAL);

        // When: Calling getPositionState().
        RebalancerSpot.PositionState memory position_ =
            rebalancerSpot.getPositionState(address(nonfungiblePositionManager), id, tick, tick, initiator);

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, poolUniswap.tickSpacing());
        {
            int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)) / tickSpacing * tickSpacing;
            int24 tickRange = position_.tickUpper - position_.tickLower;
            int24 rangeBelow = tickRange / (2 * position_.tickSpacing) * position_.tickSpacing;
            assertEq(position_.tickLower, tickCurrent - rangeBelow);
            int24 rangeAbove = tickRange - rangeBelow;
            assertEq(position_.tickUpper, tickCurrent + rangeAbove);
        }
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 twaSqrtPriceX96;
        {
            int24 twat = TwapLogic._getTwat(position_.pool);
            twaSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twat);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancerSpot.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, twaSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, twaSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV3_NewTickRange(
        RebalancerSpot.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // Declare for stack to deep.
        RebalancerSpot.PositionState memory position_;

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        uint24 POOL_FEE_ = 100;
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_);
        {
            int24 tickSpacing = poolUniswap.tickSpacing();
            require(tickSpacing == 1);

            // And: A valid position with multiple tickSpacing.
            position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
            position.tickLower = position.tickLower / tickSpacing * tickSpacing;
            position.tickUpper =
                int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
            position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
            position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
            (uint256 id,,) = addLiquidityUniV3(
                poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
            );
            (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(id);

            // And: A new position with a valid tick range.
            tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
            tickLower = tickLower / tickSpacing * tickSpacing;
            tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
            tickUpper = tickUpper / tickSpacing * tickSpacing;

            // And: The initiator is initiated.
            vm.prank(initiator);
            tolerance = bound(tolerance, 0, MAX_TOLERANCE);
            rebalancerSpot.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

            // And: The minimum time interval to calculate TWAT should have passed.
            vm.warp(block.timestamp + TwapLogic.TWAT_INTERVAL);

            // When: Calling getPositionState().
            position_ = rebalancerSpot.getPositionState(
                address(nonfungiblePositionManager), id, tickLower, tickUpper, initiator
            );
        }

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, 0);
        assertEq(position_.tickLower, tickLower);
        assertEq(position_.tickUpper, tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 twaSqrtPriceX96;
        {
            int24 twat = TwapLogic._getTwat(position_.pool);
            twaSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twat);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancerSpot.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, twaSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, twaSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_Slipstream(
        address positionManager,
        RebalancerSpot.PositionState memory position,
        uint128 liquidityPool,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: PositionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(UniswapV3Logic.POSITION_MANAGER));

        // Given: Reasonable current price.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);

        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(10) / 1000, UniswapHelpers.maxLiquidity(1) / 10));

        // Declare for stack to deep.
        RebalancerSpot.PositionState memory position_;

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        int24 TICK_SPACING_ = 1;
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool, TICK_SPACING_);
        uint24 poolFee = poolCl.fee();

        {
            require(poolFee == 100);

            // And: A valid position with multiple tickSpacing.
            position.tickLower =
                int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * TICK_SPACING_));
            position.tickLower = position.tickLower / TICK_SPACING_ * TICK_SPACING_;
            position.tickUpper =
                int24(bound(position.tickUpper, position.tickLower + 2 * TICK_SPACING_, BOUND_TICK_UPPER));
            position.tickUpper = position.tickUpper / TICK_SPACING_ * TICK_SPACING_;
            position.liquidity = uint128(bound(position.liquidity, 1e6, poolCl.liquidity() / 1e3));
            (uint256 id,,) = addLiquidityCL(
                poolCl, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
            );
            (,,,,,,, position.liquidity,,,,) = slipstreamPositionManager.positions(id);

            // And: A new position with a valid tick range.
            tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
            tickLower = tickLower / TICK_SPACING_ * TICK_SPACING_;
            tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
            tickUpper = tickUpper / TICK_SPACING_ * TICK_SPACING_;

            // And: The initiator is initiated.
            vm.prank(initiator);
            tolerance = bound(tolerance, 0, MAX_TOLERANCE);
            rebalancerSpot.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

            // And: The minimum time interval to calculate TWAT should have passed.
            vm.warp(block.timestamp + TwapLogic.TWAT_INTERVAL);

            // When: Calling getPositionState().
            position_ = rebalancerSpot.getPositionState(positionManager, id, tickLower, tickUpper, initiator);
        }

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolCl));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, poolFee);
        assertEq(position_.tickSpacing, TICK_SPACING_);
        assertEq(position_.tickLower, tickLower);
        assertEq(position_.tickUpper, tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 twaSqrtPriceX96;
        {
            int24 twat = TwapLogic._getTwat(position_.pool);
            twaSqrtPriceX96 = TickMath.getSqrtPriceAtTick(twat);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancerSpot.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, twaSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, twaSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }
}
