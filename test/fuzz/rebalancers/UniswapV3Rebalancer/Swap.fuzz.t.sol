/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";

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

    event LogHere(uint256);

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function calculateAmountToSwap(uint256 targetPercentage) external returns (uint256 amountToSwap) {
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        // Convert sqrtPriceX96 to price (P0)
        uint256 price0 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);

        // Calculate the target price (P1)
        uint256 price1 = price0 * (100 + targetPercentage) / 100;

        // Calculate the delta in token amounts (amount of token1 to swap)
        uint256 deltaY = (liquidity * liquidity * (1 << 192) * (price1 - price0)) / (price0 * price1);

        return deltaY;
    }

    /*     function test_Success_aaa(InitVariables memory initVars, LpVariables memory lpVars) public {
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        // Convert sqrtPriceX96 to price (P0)
        uint256 price0 = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);

        // Calculate the target price (P1)
        uint256 price1 = price0 * (100 + 5) / 100;

        // Calculate sqrtPriceX96 for the target price
        uint160 sqrtPrice1X96 = uint160(FixedPointMathLib.sqrt(price1 * 2 ** 96));

        // Calculate the amount of token Y to swap to achieve target price
        uint256 upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(rebalancer.UPPER_SQRT_PRICE_DEVIATION(), 1e18);
        uint256 deltaY =
            FullMath.mulDiv(uint256(liquidity), upperBoundSqrtPriceX96 - uint256(sqrtPriceX96), uint256(sqrtPriceX96));

        emit LogHere(deltaY);
    } */

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

    /*     function testFuzz_Success_swap_zeroToOne_UnbalancedPool(
        UniswapV3Rebalancer.PositionState memory position,
        bool zeroToOne
    ) public {
        // Given : zeroToOne swap
        zeroToOne = true;

        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // When : Swapping an amount that will move the price out of tolerance zone
        uint256 amount0 = 100_000 * 10 ** token0.decimals();

        // This amount will move the ticks to the left by 395 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 42_000 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    } */

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
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.upperBoundSqrtPriceX96 =
                uint256(sqrtPriceX96).mulDivDown(rebalancer.UPPER_SQRT_PRICE_DEVIATION(), 1e18);
            position.pool = address(uniV3Pool);
        }

        // Calculate the minimum amount of token Y to swap to achieve target price
        /*         uint256 deltaToken1 =
            FullMath.mulDiv(uint256(liquidity), position.upperBoundSqrtPriceX96 - uint256(sqrtPriceX96), uint256(sqrtPriceX96)); */
        uint256 deltaToken0 = FullMath.mulDiv(
            uint256(liquidity),
            (position.upperBoundSqrtPriceX96 - sqrtPriceX96) * 1e18,
            position.upperBoundSqrtPriceX96 * sqrtPriceX96
        );

        emit LogHere(deltaToken0 / 1e18);

        uint256 amountOut = deltaToken0 + (10 ** token0.decimals());

        bool isPoolUnbalanced = rebalancer.swap(position, zeroToOne, amountOut);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    /*
    function testFuzz_Success_swap_zeroToOne_balancedPool(
        UniswapV3Compounder.PositionState memory position,
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
        UniswapV3Compounder.PositionState memory position,
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
    } */
}
