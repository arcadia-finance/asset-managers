/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "./_UniswapV4Compounder.fuzz.t.sol";
import { LiquidityAmountsExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/libraries/LiquidityAmountsExtension.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";
import { UniswapV4Logic } from "../../../../src/compounders/uniswap-v4/libraries/UniswapV4Logic.sol";

/**
 * @notice Fuzz tests for the function "Swap" of contract "UniswapV4Compounder".
 */
contract Swap_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_swap_zeroAmount(UniswapV4Compounder.PositionState memory position, bool zeroToOne)
        public
    {
        // Given : amountOut is 0
        uint256 amountOut = 0;
        // When : Calling _swap()
        // Then : It should return false
        bool isPoolUnbalanced = compounder.swap(
            stablePoolKey, position.lowerBoundSqrtPriceX96, position.upperBoundSqrtPriceX96, zeroToOne, amountOut
        );
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_zeroToOne_UnbalancedPool() public {
        // Given : zeroToOne swap
        bool zeroToOne = true;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(1e18, 1e18);
        stablePoolKey =
            initializePoolV4(address(token0), address(token1), sqrtPriceX96, address(0), POOL_FEE, TICK_SPACING);

        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals()
        );

        // And : Liquidity has been added for both tokens
        mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        (, uint64 lowerSqrtPriceDeviation,) = compounder.initiatorInfo(initiator);

        uint256 lowerBoundSqrtPriceX96 = sqrtPriceX96 * uint256(lowerSqrtPriceDeviation) / 1e18;

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);

        bool isPoolUnbalanced = compounder.swap(stablePoolKey, lowerBoundSqrtPriceX96, 0, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_oneToZero_UnbalancedPool() public {
        // Given : oneToZero swap
        bool zeroToOne = false;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(1e18, 1e18);
        stablePoolKey =
            initializePoolV4(address(token0), address(token1), sqrtPriceX96, address(0), POOL_FEE, TICK_SPACING);

        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals()
        );

        // And : Liquidity has been added for both tokens
        mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        (uint64 upperSqrtPriceDeviation,,) = compounder.initiatorInfo(initiator);

        uint256 upperBoundSqrtPriceX96 = sqrtPriceX96 * uint256(upperSqrtPriceDeviation) / 1e18;

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 392 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token0.decimals();

        token1.mint(address(compounder), amount1);

        bool isPoolUnbalanced = compounder.swap(stablePoolKey, 0, upperBoundSqrtPriceX96, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_zeroToOne_balancedPool() public {
        // Given : zeroToOne swap
        bool zeroToOne = true;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(1e18, 1e18);
        stablePoolKey =
            initializePoolV4(address(token0), address(token1), sqrtPriceX96, address(0), POOL_FEE, TICK_SPACING);

        // And : Liquidity has been added for both tokens
        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals()
        );

        mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        (, uint64 lowerSqrtPriceDeviation,) = compounder.initiatorInfo(initiator);

        uint256 lowerBoundSqrtPriceX96 = sqrtPriceX96 * uint256(lowerSqrtPriceDeviation) / 1e18;

        // When : Swapping an amount that will move the price at limit of tolerance (still withing tolerance)
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which is at the limit of the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 40_000 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);

        bool isPoolUnbalanced = compounder.swap(stablePoolKey, lowerBoundSqrtPriceX96, 0, zeroToOne, amountOut);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_oneToZero_balancedPool() public {
        // Given : oneToZero swap
        bool zeroToOne = false;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV4Logic._getSqrtPriceX96(1e18, 1e18);
        stablePoolKey =
            initializePoolV4(address(token0), address(token1), sqrtPriceX96, address(0), POOL_FEE, TICK_SPACING);

        // And : Liquidity has been added for both tokens
        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals()
        );

        mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        (uint64 upperSqrtPriceDeviation,,) = compounder.initiatorInfo(initiator);

        uint256 upperBoundSqrtPriceX96 = sqrtPriceX96 * uint256(upperSqrtPriceDeviation) / 1e18;

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 384 which is still below tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 39_000 * 10 ** token0.decimals();

        token1.mint(address(compounder), amount1);

        bool isPoolUnbalanced = compounder.swap(stablePoolKey, 0, upperBoundSqrtPriceX96, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, false);
    }
}
