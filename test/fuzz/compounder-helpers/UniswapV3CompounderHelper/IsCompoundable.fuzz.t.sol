/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { UniswapV3CompounderHelper_Fuzz_Test } from "./_UniswapV3CompounderHelper.fuzz.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3CompounderHelper_Fuzz_Test } from "./_UniswapV3CompounderHelper.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/compounders/uniswap-v3/libraries/UniswapV3Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "isCompoundable" of contract "UniswapV3CompounderHelperLogic".
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
        vm.prank(initiator);
        uniswapV3Compounder.setInitiatorInfo(TOLERANCE, initiatorShare);

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
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(nonfungiblePositionManager), address(account));

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
        vm.prank(initiator);
        uniswapV3Compounder.setInitiatorInfo(TOLERANCE, initiatorShare);

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
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(nonfungiblePositionManager), address(account));

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

        // And : We generate a small 4$ of fees.
        generateFees(2, 2);

        // When : Calling isCompoundable()
        (bool isCompoundable_, address compounder_, uint160 sqrtPriceX96_) =
            compounderHelper.isCompoundable(tokenId, address(nonfungiblePositionManager), address(account));
        assertEq(isCompoundable_, true);
        assertEq(compounder_, address(uniswapV3Compounder));
        (sqrtPriceX96,,,,,,) = usdStablePool.slot0();
        assertEq(sqrtPriceX96, sqrtPriceX96_);

        vm.prank(initiator);
        uniswapV3Compounder.compoundFees(address(account), tokenId, uint256(sqrtPriceX96_));
    }
}
