/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/uniswap-v3/LiquidityAmounts.sol";
import { SwapMath } from "../../../utils/uniswap-v3/SwapMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/rebalancers/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "swapViaPool" of contract "Rebalancer".
 */
contract SwapViaPool_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
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

    function testFuzz_Success_swapViaPool_ZeroAmount(Rebalancer.PositionState memory position, bool zeroToOne) public {
        // Given : amountOut is 0
        uint256 amountOut = 0;
        // When : Calling _swap()
        // Then : It should return false
        bool isPoolUnbalanced = rebalancer.swapViaPool(position, zeroToOne, amountOut);
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swapViaPool_OneToZero_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swapViaPool
        zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation,,,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice above upperBound target to be sure we exceed it
        uint256 sqrtPriceX96Target =
            position.upperBoundSqrtPriceX96 + ((position.upperBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = -int256(type(int128).max);
        // Calculate the amounts to swapViaPool to achieve target price.
        (, uint256 amountIn, uint256 amountOut, uint256 feeAmount) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swapViaPool
        deal(address(token1), address(rebalancer), amountIn + feeAmount);

        bool isPoolUnbalanced = rebalancer.swapViaPool(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swapViaPool_OneToZero_BalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swapViaPool
        zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation,,,) = rebalancer.initiatorInfo(initVars.initiator);
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
        // Calculate the amounts to swapViaPool to achieve target price.
        (, uint256 amountIn, uint256 amountOut, uint256 feeAmount) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, -amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swapViaPool
        deal(address(token1), address(rebalancer), amountIn + feeAmount);

        bool isPoolUnbalanced = rebalancer.swapViaPool(position, zeroToOne, amountOut);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swapViaPool
        zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice below lowerBound target to be sure we exceed it
        uint256 sqrtPriceX96Target =
            position.lowerBoundSqrtPriceX96 - ((position.lowerBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = -type(int128).max;
        // Calculate the amounts to swapViaPool to achieve target price.
        (, uint256 amountIn, uint256 amountOut, uint256 feeAmount) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swapViaPool
        deal(address(token0), address(rebalancer), amountIn + feeAmount);

        bool isPoolUnbalanced = rebalancer.swapViaPool(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swapViaPool_ZeroToOne_BalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swapViaPool
        zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (, uint256 lowerSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Take 0,1% sqrtPrice above lowerBound target to be sure we are still in range
        uint256 sqrtPriceX96Target =
            position.lowerBoundSqrtPriceX96 + ((position.lowerBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

        int256 amountRemaining = -type(int128).max;
        // Calculate the amounts to swapViaPool to achieve target price.
        (, uint256 amountIn, uint256 amountOut, uint256 feeAmount) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
        );

        // Send amountIn to rebalancer for swapViaPool
        deal(address(token0), address(rebalancer), amountIn + feeAmount);

        bool isPoolUnbalanced = rebalancer.swapViaPool(position, zeroToOne, amountOut);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
