/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounderHelper_Fuzz_Test } from "./_SlipstreamCompounderHelper.fuzz.t.sol";
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

        // Set smaller initiator share
        uint256 initiatorShare = 0.005 * 1e18;
        vm.prank(initiator);
        slipstreamCompounder.setInitiatorInfo(TOLERANCE, initiatorShare);

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
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(slipstreamPositionManager), address(account));

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
        vm.prank(initiator);
        slipstreamCompounder.setInitiatorInfo(TOLERANCE, initiatorShare);

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
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(slipstreamPositionManager), address(account));

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

        // And : We generate small fees of 4$
        generateFees(2, 2);

        // When : Calling isCompoundable()
        (bool isCompoundable_,,) =
            compounderHelper.isCompoundable(tokenId, address(slipstreamPositionManager), address(account));
        assertEq(isCompoundable_, true);
    }
}
