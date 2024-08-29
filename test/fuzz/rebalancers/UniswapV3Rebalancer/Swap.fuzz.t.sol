/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { SwapMath } from "../../../../src/libraries/SwapMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "Swap" of contract "UniswapV3Rebalancer".
 */
contract Swap_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_swap_zeroAmount(UniswapV3Rebalancer.PositionState memory position, bool zeroToOne)
        public
    {
        // Given : amountOut is 0
        uint256 amountOut = 0;
        // When : Calling _swap()
        // Then : It should return false
        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountOut);
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_oneToZero_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swap
        zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice above upperBound target to be sure we exceed it
        uint256 sqrtPriceX96Target =
            position.upperBoundSqrtPriceX96 + ((position.upperBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = int256(type(int128).max);
        // Calculate the minimum amount of token 1 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swap
        deal(address(token1), address(rebalancer), amountIn);

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountIn);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_oneToZero_balancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swap
        zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice below upperBound target to be sure we are just below
        uint256 sqrtPriceX96Target =
            position.upperBoundSqrtPriceX96 - ((position.upperBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = int256(type(int128).max);
        // Calculate the minimum amount of token 1 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send token1 to rebalancer for swap
        deal(address(token1), address(rebalancer), amountIn);

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountIn);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_zeroToOne_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swap
        zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (, uint256 lowerSqrtPriceDeviation,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice below lowerBound target to be sure we exceed it
        uint256 sqrtPriceX96Target =
            position.lowerBoundSqrtPriceX96 - ((position.lowerBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the minimum amount of token 0 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swap
        deal(address(token0), address(rebalancer), amountIn);

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountIn);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_zeroToOne_BalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swap
        zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (, uint256 lowerSqrtPriceDeviation,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice above lowerBound target to be sure we are still in range
        uint256 sqrtPriceX96Target =
            position.lowerBoundSqrtPriceX96 + ((position.lowerBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the minimum amount of token 0 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send tokenIn to rebalancer for swap
        deal(address(token0), address(rebalancer), amountIn);

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountIn);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
