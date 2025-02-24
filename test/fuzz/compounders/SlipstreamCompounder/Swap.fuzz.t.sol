/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamCompounder } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";
import { SlipstreamLogic } from "../../../../src/compounders/slipstream/libraries/SlipstreamLogic.sol";

/**
 * @notice Fuzz tests for the function "Swap" of contract "SlipstreamCompounder".
 */
contract Swap_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_swap_zeroAmount(SlipstreamCompounder.PositionState memory position, bool zeroToOne)
        public
    {
        // Given : amountOut is 0
        uint256 amountOut = 0;
        // When : Calling _swap()
        // Then : It should return false
        bool isPoolUnbalanced = compounder.swap(position, zeroToOne, amountOut);
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_zeroToOne_UnbalancedPool(
        SlipstreamCompounder.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swap
        zeroToOne = true;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityCL(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.tickSpacing = TICK_SPACING;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * compounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);

        bool isPoolUnbalanced = compounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_oneToZEro_UnbalancedPool(
        SlipstreamCompounder.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swap
        zeroToOne = false;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityCL(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.tickSpacing = TICK_SPACING;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 392 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token0.decimals();

        token1.mint(address(compounder), amount1);

        bool isPoolUnbalanced = compounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_Success_swap_zeroToOne_balancedPool(
        SlipstreamCompounder.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swap
        zeroToOne = true;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityCL(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.tickSpacing = TICK_SPACING;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * compounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price at limit of tolerance (still withing tolerance)
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which is at the limit of the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 40_000 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);

        bool isPoolUnbalanced = compounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_Success_swap_oneToZero_balancedPool(
        SlipstreamCompounder.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : oneToZero swap
        zeroToOne = false;

        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityCL(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.tickSpacing = TICK_SPACING;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 384 which is still below tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 39_000 * 10 ** token0.decimals();

        token1.mint(address(compounder), amount1);

        bool isPoolUnbalanced = compounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, false);
    }
}
