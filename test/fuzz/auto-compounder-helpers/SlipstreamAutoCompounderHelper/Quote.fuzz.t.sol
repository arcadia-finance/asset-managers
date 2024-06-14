/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ISlipstreamAutoCompounder } from "../../../../src/auto-compounder/interfaces/ISlipstreamAutoCompounder.sol";
import { PositionState } from "../../../../src/auto-compounder/interfaces/ISlipstreamAutoCompounder.sol";
import { SlipstreamAutoCompounder } from "../../../../src/auto-compounder/SlipstreamAutoCompounder.sol";
import { SlipstreamAutoCompoundHelper_Fuzz_Test } from "./_SlipstreamAutoCompoundHelper.fuzz.t.sol";
import { SlipstreamLogic } from "../../../../src/auto-compounder/libraries/SlipstreamLogic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "_quote" of contract "SlipstreamAutoCompoundHelper".
 */
contract Quote_SlipstreamAutoCompoundHelper_Fuzz_Test is SlipstreamAutoCompoundHelper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        SlipstreamAutoCompoundHelper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_success_quote_false_poolIsUnbalanced(PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
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
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Calling quote()
        // AmountOut of 42_000 will move the ticks to the right by 392 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        bool isPoolUnbalanced = autoCompoundHelper.quote(position, true, 42_000 * 1e18);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_quote(PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** token0.decimals()));
        addAssetToArcadia(address(token1), int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = SlipstreamLogic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
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
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Calling quote()
        // AmountOut of 40_000 will move the ticks to the right by 392 at limit of tolerance (still in limits)
        bool isPoolUnbalanced = autoCompoundHelper.quote(position, true, 40_000 * 1e18);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }
}
