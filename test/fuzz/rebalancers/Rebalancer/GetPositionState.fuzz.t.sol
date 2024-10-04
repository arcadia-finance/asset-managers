/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/PricingLogic.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer2.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "Rebalancer".
 */
contract GetPositionState_SwapLogic_Fuzz_Test is Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_UniswapV3_SameTickRange_OneTickSpacing(
        Rebalancer.PositionState memory position,
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
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

        // When: Calling getPositionState().
        Rebalancer.PositionState memory position_ =
            rebalancer.getPositionState(address(nonfungiblePositionManager), id, tick, tick, initiator);

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, poolUniswap.tickSpacing());
        int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96)) / tickSpacing * tickSpacing;
        assertEq(position_.tickLower, tickCurrent);
        assertEq(position_.tickUpper, position_.tickLower + tickSpacing);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtRatioAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 price0 = 1e18;
        uint256 price1 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV3_SameTickRange_MultipleTickSpacings(
        Rebalancer.PositionState memory position,
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
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

        // When: Calling getPositionState().
        Rebalancer.PositionState memory position_ =
            rebalancer.getPositionState(address(nonfungiblePositionManager), id, tick, tick, initiator);

        // Then : It should return the correct values
        assertEq(position_.pool, address(poolUniswap));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, poolUniswap.tickSpacing());
        {
            int24 tickCurrent = TickMath.getTickAtSqrtRatio(uint160(position.sqrtPriceX96)) / tickSpacing * tickSpacing;
            int24 tickRange = position_.tickUpper - position_.tickLower;
            int24 rangeBelow = tickRange / (2 * position_.tickSpacing) * position_.tickSpacing;
            assertEq(position_.tickLower, tickCurrent - rangeBelow);
            int24 rangeAbove = tickRange - rangeBelow;
            assertEq(position_.tickUpper, tickCurrent + rangeAbove);
        }
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtRatioAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 trustedSqrtPriceX96;
        {
            uint256 price0 = 1e18;
            uint256 price1 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV3_NewTickRange(
        Rebalancer.PositionState memory position,
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
        Rebalancer.PositionState memory position_;

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
            rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

            // When: Calling getPositionState().
            position_ =
                rebalancer.getPositionState(address(nonfungiblePositionManager), id, tickLower, tickUpper, initiator);
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
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtRatioAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 trustedSqrtPriceX96;
        {
            uint256 price0 = 1e18;
            uint256 price1 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_Slipstream(
        address positionManager,
        Rebalancer.PositionState memory position,
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
        Rebalancer.PositionState memory position_;

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
            rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE);

            // When: Calling getPositionState().
            position_ = rebalancer.getPositionState(positionManager, id, tickLower, tickUpper, initiator);
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
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtRatioAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtRatioAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 trustedSqrtPriceX96;
        {
            uint256 price0 = 1e18;
            uint256 price1 = FullMath.mulDiv(1e18, position.sqrtPriceX96 ** 2, PricingLogic.Q192);
            trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(price0, price1);
        }
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }
}
