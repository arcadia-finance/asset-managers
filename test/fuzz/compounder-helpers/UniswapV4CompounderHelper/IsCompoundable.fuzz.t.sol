/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { LiquidityAmountsExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/libraries/LiquidityAmountsExtension.sol";
import { UniswapV3Logic } from "../../../../src/compounders/uniswap-v3/libraries/UniswapV3Logic.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4CompounderHelper_Fuzz_Test } from "./_UniswapV4CompounderHelper.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "isCompoundable" of contract "UniswapV4CompounderHelper".
 */
contract IsCompoundable_UniswapV4CompounderHelper_Fuzz_Test is UniswapV4CompounderHelper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        UniswapV4CompounderHelper_Fuzz_Test.setUp();
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
        uint160 sqrtPrice = UniswapV3Logic._getSqrtPrice(1e18, 1e18);

        stablePoolKey =
            initializePoolV4(address(token0), address(token1), uint160(sqrtPrice), address(0), fee, TICK_SPACING);

        // Set smaller initiator share.
        uint256 initiatorShare = 0.005 * 1e18;
        vm.prank(initiator);
        uniswapV4Compounder.setInitiatorInfo(TOLERANCE, initiatorShare);

        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals()
        );

        // Liquidity has been added for both tokens
        uint256 tokenId = mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        // And : Generate fees on one side.
        FeeGrowth memory feeData;
        feeData.desiredFee0 = 20;
        feeData.desiredFee1 = 0;

        setFeeState(feeData, stablePoolKey, uint128(liquidity));

        // When : Calling isCompoundable()
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(positionManagerV4), address(account));

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
        uint160 sqrtPrice = UniswapV3Logic._getSqrtPrice(1e18, 1e18);

        stablePoolKey =
            initializePoolV4(address(token0), address(token1), uint160(sqrtPrice), address(0), fee, TICK_SPACING);

        // Set smaller initiator share.
        uint256 initiatorShare = 0.005 * 1e18;
        vm.prank(initiator);
        uniswapV4Compounder.setInitiatorInfo(TOLERANCE, initiatorShare);

        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals()
        );

        // Liquidity has been added for both tokens
        uint256 tokenId = mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        // And : Generate fees on one side.
        FeeGrowth memory feeData;
        feeData.desiredFee0 = 0;
        feeData.desiredFee1 = 20;

        setFeeState(feeData, stablePoolKey, uint128(liquidity));

        // When : Calling isCompoundable()
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(positionManagerV4), address(account));

        // Then : It should return "false"
        assertEq(isCompoundable_, false);
    }

    function testFuzz_Success_isCompoundable() public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        // Create pool with 1% trade fee.
        uint160 sqrtPrice = UniswapV3Logic._getSqrtPrice(1e18, 1e18);
        stablePoolKey =
            initializePoolV4(address(token0), address(token1), uint160(sqrtPrice), address(0), POOL_FEE, TICK_SPACING);

        uint256 liquidity = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPrice,
            TickMath.getSqrtPriceAtTick(-1000),
            TickMath.getSqrtPriceAtTick(1000),
            1_000_000 * 10 ** token0.decimals(),
            1_000_000 * 10 ** token1.decimals()
        );

        // Liquidity has been added for both tokens
        uint256 tokenId = mintPositionV4(
            stablePoolKey, -1000, 1000, liquidity, type(uint128).max, type(uint128).max, users.liquidityProvider
        );

        // And : We generate a small 4$ of fees.
        FeeGrowth memory feeData;
        feeData.desiredFee0 = 2;
        feeData.desiredFee1 = 2;

        setFeeState(feeData, stablePoolKey, uint128(liquidity));

        // When : Calling isCompoundable()
        (bool isCompoundable_, address compounder_, uint160 sqrtPrice_) =
            compounderHelper.isCompoundable(tokenId, address(positionManagerV4), address(account));

        // Then : It should return "true"
        assertEq(isCompoundable_, true);
        assertEq(compounder_, address(uniswapV4Compounder));
        assertEq(sqrtPrice, sqrtPrice_);
    }
}
