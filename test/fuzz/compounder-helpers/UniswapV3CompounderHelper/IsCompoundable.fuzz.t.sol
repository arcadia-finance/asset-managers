/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3CompounderHelper_Fuzz_Test } from "./_UniswapV3CompounderHelper.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/compounders/uniswap-v3/libraries/UniswapV3Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "isCompoundable" of contract "UniswapV3CompounderHelper".
 */
contract IsCompoundable_UniswapV3CompounderHelper_Fuzz_Test is UniswapV3CompounderHelper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        UniswapV3CompounderHelper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_isCompoundable_false_initiallyUnbalanced(
        UniswapV3Compounder.PositionState memory position
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
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * compounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : We generate one sided fees to move the pool in an unbalanced state
        generateFees(1000, 1);
        (position.sqrtPriceX96,,,,,,) = usdStablePool.slot0();

        // And : Ensure isCompoundable returns false for being unbalanced
        bool poolIsUnbalanced = compounder.isPoolUnbalanced(position);
        assertEq(poolIsUnbalanced, true);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_false_feesBelowThreshold(UniswapV3Compounder.PositionState memory position)
        public
    {
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
            position.fee = POOL_FEE;
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
        UniswapV3Compounder.PositionState memory position
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
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        addLiquidityUniV3(
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
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * compounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * compounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // And : Generate fees only for fee1
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
        uint24 fee = 1e4;
        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), fee, sqrtPriceX96, 300);

        // Redeploy compounder with small initiator share
        uint256 initiatorShare = 0.005 * 1e18;
        deployCompounder(COMPOUND_THRESHOLD, initiatorShare, TOLERANCE);
        deployCompounderHelper();

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
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
        uint24 fee = 1e4;
        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolUniV3(address(token0), address(token1), fee, sqrtPriceX96, 300);

        // Redeploy compounder with small initiator share
        uint256 initiatorShare = 0.005 * 1e18;
        deployCompounder(COMPOUND_THRESHOLD, initiatorShare, TOLERANCE);
        deployCompounderHelper();

        // Liquidity has been added for both tokens
        (uint256 tokenId,,) = addLiquidityUniV3(
            usdStablePool,
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );

        // And : Generate on one side.
        generateFees(0, 20);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable_true() public {
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
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000,
            true
        );
        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : We generate 11$ of fees, which is above 10$ threshold
        generateFees(6, 5);

        // When : Calling isCompoundable()
        bool isCompoundable_ = compounderHelper.isCompoundable(tokenId);
        assertEq(isCompoundable_, true);

        compounder.compoundFees(address(account), tokenId);
    }
}
