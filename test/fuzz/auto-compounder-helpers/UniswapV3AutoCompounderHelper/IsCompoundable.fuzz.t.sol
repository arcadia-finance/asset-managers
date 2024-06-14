/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { UniswapV3AutoCompounder } from "../../../../src/auto-compounders/uniswap-v3/UniswapV3AutoCompounder.sol";
import { UniswapV3AutoCompoundHelper_Fuzz_Test } from "./_UniswapV3AutoCompoundHelper.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/auto-compounders/uniswap-v3/libraries/UniswapV3Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "isCompoundable" of contract "UniswapV3AutoCompoundHelper".
 */
contract IsCompoundable_UniswapV3AutoCompoundHelper_Fuzz_Test is UniswapV3AutoCompoundHelper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        UniswapV3AutoCompoundHelper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_success_isCompoundable_false_initiallyUnbalanced(
        UniswapV3AutoCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate one sided fees to move the pool in an unbalanced state
        generateFees(1000, 1);

        // And : Ensure isCompoundable returns false for being unbalanced
        bool poolIsUnbalanced = autoCompounder.isPoolUnbalanced(position);
        assertEq(poolIsUnbalanced, true);

        // When : Calling isCompoundable()
        bool isCompoundable_ = autoCompoundHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_success_isCompoundable_false_feesBelowThreshold(
        UniswapV3AutoCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate 9$ of fees, which is below 10$ threshold
        generateFees(4, 5);

        // When : Calling isCompoundable()
        bool isCompoundable_ = autoCompoundHelper.isCompoundable(tokenId);
        assertEq(isCompoundable_, false);
    }

    function testFuzz_success_isCompoundable_false_unbalancedAfterFeeSwap(
        UniswapV3AutoCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : Generate fees on both sides
        generateFees(20, 20);

        // And : Swap to limit of tolerance (still within limits) in order for the next fee swap to exceed tolerance
        uint256 amount0 = 100_000 * 10 ** token0.decimals();
        // This amount will move the ticks to the left by 395 which is at the limit of the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 40_000 * 10 ** token1.decimals();

        token0.mint(address(autoCompounder), amount0);
        autoCompounder.swap(position, true, amountOut);

        // When : Calling isCompoundable()
        bool isCompoundable_ = autoCompoundHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_success_isCompoundable_true(UniswapV3AutoCompounder.PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate 11$ of fees, which is above 10$ threshold
        generateFees(6, 5);

        // When : Calling isCompoundable()
        bool isCompoundable_ = autoCompoundHelper.isCompoundable(tokenId);
        assertEq(isCompoundable_, true);
    }
}
