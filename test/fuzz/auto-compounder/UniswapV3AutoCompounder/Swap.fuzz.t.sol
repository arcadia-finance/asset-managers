/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "./_UniswapV3AutoCompounder.fuzz.t.sol";
import { UniswapV3AutoCompounder } from "./_UniswapV3AutoCompounder.fuzz.t.sol";
import { UniswapV3AutoCompounder_Fuzz_Test } from "./_UniswapV3AutoCompounder.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/auto-compounder/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "Swap" of contract "UniswapV3AutoCompounder".
 */
contract Swap_UniswapV3AutoCompounder_Fuzz_Test is UniswapV3AutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3AutoCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_success_swap_zeroAmount(UniswapV3AutoCompounder.PositionState memory position, bool zeroToOne)
        public
    {
        // Given : amountOut is 0
        uint256 amountOut = 0;
        // When : Calling _swap()
        // Then : It should return false
        bool isPoolUnbalanced = autoCompounder.swap(position, zeroToOne, amountOut);
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_success_swap_zeroToOne_UnbalancedPool(
        UniswapV3AutoCompounder.PositionState memory position,
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

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityUniV3(
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
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token1.decimals();

        token0.mint(address(autoCompounder), amount0);

        bool isPoolUnbalanced = autoCompounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_swap_oneToZEro_UnbalancedPool(
        UniswapV3AutoCompounder.PositionState memory position,
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

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityUniV3(
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
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 392 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token0.decimals();

        token1.mint(address(autoCompounder), amount1);

        bool isPoolUnbalanced = autoCompounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_swap_zeroToOne_balancedPool(
        UniswapV3AutoCompounder.PositionState memory position,
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

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityUniV3(
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
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price at limit of tolerance (still withing tolerance)
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which is at the limit of the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 40_000 * 10 ** token1.decimals();

        token0.mint(address(autoCompounder), amount0);

        bool isPoolUnbalanced = autoCompounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    function testFuzz_success_swap_oneToZero_balancedPool(
        UniswapV3AutoCompounder.PositionState memory position,
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

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // And : Liquidity has been added for both tokens
        addLiquidityUniV3(
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
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount1 = 100_000 * 10 ** token1.decimals();

        // This amount will move the ticks to the right by 384 which is still below tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 39_000 * 10 ** token0.decimals();

        token1.mint(address(autoCompounder), amount1);

        bool isPoolUnbalanced = autoCompounder.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, false);
    }
}
