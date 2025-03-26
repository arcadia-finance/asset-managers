/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/cl-math/PricingLogic.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/uniswap-v3/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "RebalancerUniswapV4".
 */
contract GetPositionState_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_UniswapV4_SameTickRange_OneTickSpacing(
        RebalancerUniswapV4.PositionState memory position,
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

        // And: A pool with liquidity with tickSpacing 10 and fee = 500.
        uint24 POOL_FEE_ = 500;
        int24 TICK_SPACING_ = 1;
        initPoolAndAddLiquidity(
            uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_, TICK_SPACING_, address(validHook)
        );

        // And: A valid position with one tick spacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - TICK_SPACING_));
        position.tickLower = position.tickLower / TICK_SPACING_ * TICK_SPACING_;
        position.tickUpper = position.tickLower + TICK_SPACING_;
        position.liquidity = uint128(bound(position.liquidity, 1e6, stateView.getLiquidity(v4PoolKey.toId()) / 1e3));
        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id)));
        position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // When: Calling getPositionState().
        RebalancerUniswapV4.PositionState memory position_ =
            rebalancer.getPositionState(id, tick, tick, position.sqrtPriceX96, initiator);

        // Then : It should return the correct values
        assertEq(position_.hook, address(validHook));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, TICK_SPACING_);
        int24 tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)) / TICK_SPACING_ * TICK_SPACING_;
        assertEq(position_.tickLower, tickCurrent);
        assertEq(position_.tickUpper, position_.tickLower + TICK_SPACING_);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, position_.sqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, position_.sqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV4_SameTickRange_MultipleTickSpacings(
        RebalancerUniswapV4.PositionState memory position,
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
        int24 TICK_SPACING_ = 10;
        initPoolAndAddLiquidity(
            uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_, TICK_SPACING_, address(validHook)
        );

        // And: A valid position with multiple tickSpacing.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * TICK_SPACING_));
        position.tickLower = position.tickLower / TICK_SPACING_ * TICK_SPACING_;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * TICK_SPACING_, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / TICK_SPACING_ * TICK_SPACING_;
        position.liquidity = uint128(bound(position.liquidity, 1e6, stateView.getLiquidity(v4PoolKey.toId()) / 1e3));
        uint256 id = mintPositionV4(
            v4PoolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id)));
        position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

        // And: The initiator is initiated.
        vm.prank(initiator);
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // When: Calling getPositionState().
        RebalancerUniswapV4.PositionState memory position_ =
            rebalancer.getPositionState(id, tick, tick, position.sqrtPriceX96, initiator);

        // Then : It should return the correct values
        assertEq(position_.hook, address(validHook));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, TICK_SPACING_);
        {
            int24 tickCurrent =
                TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96)) / TICK_SPACING_ * TICK_SPACING_;
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
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }

    function testFuzz_Success_getPositionState_UniswapV4_NewTickRange(
        RebalancerUniswapV4.PositionState memory position,
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
        RebalancerUniswapV4.PositionState memory position_;

        // And: A pool with liquidity with tickSpacing 1 (fee = 100).
        uint24 POOL_FEE_ = 100;
        int24 TICK_SPACING_ = 1;
        initPoolAndAddLiquidity(
            uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE_, TICK_SPACING_, address(validHook)
        );
        {
            // And: A valid position with multiple tickSpacing.
            position.tickLower =
                int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * TICK_SPACING_));
            position.tickLower = position.tickLower / TICK_SPACING_ * TICK_SPACING_;
            position.tickUpper =
                int24(bound(position.tickUpper, position.tickLower + 2 * TICK_SPACING_, BOUND_TICK_UPPER));
            position.tickUpper = position.tickUpper / TICK_SPACING_ * TICK_SPACING_;
            position.liquidity = uint128(bound(position.liquidity, 1e6, stateView.getLiquidity(v4PoolKey.toId()) / 1e3));
            uint256 id = mintPositionV4(
                v4PoolKey,
                position.tickLower,
                position.tickUpper,
                position.liquidity,
                type(uint128).max,
                type(uint128).max,
                users.liquidityProvider
            );
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(id))
            );
            position.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

            // And: A new position with a valid tick range.
            tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 1));
            tickLower = tickLower / TICK_SPACING_ * TICK_SPACING_;
            tickUpper = int24(bound(tickUpper, tickLower + 1, BOUND_TICK_UPPER));
            tickUpper = tickUpper / TICK_SPACING_ * TICK_SPACING_;

            // And: The initiator is initiated.
            vm.prank(initiator);
            tolerance = bound(tolerance, 0, MAX_TOLERANCE);
            rebalancer.setInitiatorInfo(tolerance, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

            // When: Calling getPositionState().
            position_ = rebalancer.getPositionState(id, tickLower, tickUpper, position.sqrtPriceX96, initiator);
        }

        // Then : It should return the correct values
        assertEq(position_.hook, address(validHook));
        assertEq(position_.token0, address(token0));
        assertEq(position_.token1, address(token1));
        assertEq(position_.fee, POOL_FEE_);
        assertEq(position_.tickSpacing, 1);
        assertEq(position_.tickLower, tickLower);
        assertEq(position_.tickUpper, tickUpper);
        assertEq(position_.liquidity, position.liquidity);
        assertEq(position_.sqrtRatioLower, TickMath.getSqrtPriceAtTick(position_.tickLower));
        assertEq(position_.sqrtRatioUpper, TickMath.getSqrtPriceAtTick(position_.tickUpper));
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
        uint256 trustedSqrtPriceX96 = position.sqrtPriceX96;
        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initiator);
        assertEq(position_.lowerBoundSqrtPriceX96, trustedSqrtPriceX96 * lowerSqrtPriceDeviation / 1e18);
        assertEq(position_.upperBoundSqrtPriceX96, trustedSqrtPriceX96 * upperSqrtPriceDeviation / 1e18);
    }
}
