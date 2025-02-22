/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamCompounderHelper_Fuzz_Test } from "./_SlipstreamCompounderHelper.fuzz.t.sol";
import { SlipstreamLogic } from "../../../../src/compounders/slipstream/libraries/SlipstreamLogic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "isCompoundable" of contract "SlipstreamCompounderHelper".
 */
contract IsCompoundable_SlipstreamCompounderHelper_Fuzz_Test is SlipstreamCompounderHelper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        SlipstreamCompounderHelper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_isCompoundable_false_initiallyUnbalanced(
        SlipstreamCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate one sided fees to move the pool in an unbalanced state
        generateFees(1000, 1);
        (position.sqrtPriceX96,,,,,) = usdStablePool.slot0();

        // And : Ensure isCompoundable returns false for being unbalanced
        bool poolIsUnbalanced = compounder.isPoolUnbalanced(position);
        assertEq(poolIsUnbalanced, true);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_false_feesBelowThreshold(
        SlipstreamCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate 9$ of fees, which is below 10$ threshold
        generateFees(4, 5);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_false_unbalancedAfterFeeSwap(
        SlipstreamCompounder.PositionState memory position
    ) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        addLiquidityCL(
            usdStablePool,
            10_000_000 * 10 ** token0.decimals(),
            10_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -10_000,
            10_000,
            true
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.tickSpacing = TICK_SPACING;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * compounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : Generate fees on both sides
        generateFees(20, 20);

        // And : Swap to limit of tolerance (still within limits) in order for the next fee swap to exceed tolerance
        uint256 amount0 = 1e18 * 10 ** token0.decimals();
        // This amount will move the ticks to the left by 395 which is at the limit of the tolerance of 4% (1 tick +- 0,01%).
        uint256 amountOut = 928_660 * 10 ** token1.decimals();

        token0.mint(address(compounder), amount0);
        compounder.swap(position, true, amountOut);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_false_InsufficientToken0() public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        // Create pool with 1% trade fee.
        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), 2000, sqrtPriceX96, 300);
        usdStablePool.fee();

        // Redeploy compounder with small initiator share
        uint256 initiatorShare = 0.005 * 1e18;
        deployCompounder(COMPOUND_THRESHOLD, initiatorShare, TOLERANCE);
        deployCompounderHelper();

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -2000,
            2000,
            true
        );

        // And : Generate on one side.
        generateFees(20, 0);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_false_InsufficientToken1() public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        // Create pool with 1% trade fee.
        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), 2000, sqrtPriceX96, 300);

        // Redeploy compounder with small initiator share
        uint256 initiatorShare = 0.005 * 1e18;
        deployCompounder(COMPOUND_THRESHOLD, initiatorShare, TOLERANCE);
        deployCompounderHelper();

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -2000,
            2000,
            true
        );

        // And : Generate on one side.
        generateFees(0, 20);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_true(SlipstreamCompounder.PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityCL(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
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
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate 11$ of fees, which is above 10$ threshold
        generateFees(6, 5);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);
        assertEq(isCompoundable_, true);
    }
}
