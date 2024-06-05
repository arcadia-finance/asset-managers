/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder_Fuzz_Test, AutoCompounder } from "../auto-compounder/_AutoCompounder.fuzz.t.sol";

import { UniswapV3Logic } from "../../../src/auto-compounder/AutoCompounderViews.sol";
import { AutoCompounderViewsExtension } from "../../utils/extensions/AutoCompounderViewsExtension.sol";
import { ERC20Mock } from "../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Utils } from "../../../lib/accounts-v2/test/utils/Utils.sol";
import { IAutoCompounder } from "../../../src/auto-compounder/interfaces/IAutoCompounder.sol";

/**
 * @notice Fuzz tests for the function "_quote" of contract "AutoCompounderViews".
 */
contract Quote_AutoCompounderViews_Fuzz_Test is AutoCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////  
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    AutoCompounderViewsExtension public compounderViews;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        AutoCompounder_Fuzz_Test.setUp();

        deployAutoCompounderViews();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_success_quote_false_poolIsUnbalanced(IAutoCompounder.PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        AddAsset(token0, int256(10 ** token0.decimals()));
        AddAsset(token1, int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPool(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        addLiquidity(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Calling quote()
        // AmountOut of 42_000 will move the ticks to the right by 392 which exceeds the tolerance of 4% (1 tick +- 0,01%).
        bool isPoolUnbalanced = compounderViews.quote(position, true, 42_000 * 1e18);

        // Then : It should return "true"
        assertEq(isPoolUnbalanced, true);
    }

    function testFuzz_success_quote(IAutoCompounder.PositionState memory position) public {
        // Given : New balanced stable pool 1:1
        token0 = new ERC20Mock("Token0", "TOK0", 18);
        token1 = new ERC20Mock("Token1", "TOK1", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        AddAsset(token0, int256(10 ** token0.decimals()));
        AddAsset(token1, int256(10 ** token1.decimals()));

        uint160 sqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(1e18, 1e18);
        usdStablePool = createPool(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Liquidity has been added for both tokens
        addLiquidity(
            usdStablePool,
            100_000 * 10 ** token0.decimals(),
            100_000 * 10 ** token1.decimals(),
            users.liquidityProvider,
            -1000,
            1000
        );

        {
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.fee = POOL_FEE;
            position.lowerBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.LOWER_SQRT_PRICE_DEVIATION() / 1e18;
            position.upperBoundSqrtPriceX96 = sqrtPriceX96 * autoCompounder.UPPER_SQRT_PRICE_DEVIATION() / 1e18;
            position.pool = address(usdStablePool);
        }

        // When : Calling quote()
        // AmountOut of 40_000 will move the ticks to the right by 392 at limit of tolerance (still in limits)
        bool isPoolUnbalanced = compounderViews.quote(position, true, 40_000 * 1e18);

        // Then : It should return "false"
        assertEq(isPoolUnbalanced, false);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
    function deployAutoCompounderViews() public {
        vm.prank(users.deployer);
        compounderViews = new AutoCompounderViewsExtension(address(autoCompounder));

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(compounderViews).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in AutoCompounderViews.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1),
            abi.encodePacked(nonfungiblePositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x33128a8fC17869897dcE68Ed026d694621f6FDfD),
            abi.encodePacked(uniswapV3Factory),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a), abi.encodePacked(quoter), false
        );
        vm.etch(address(compounderViews), bytecode);
    }
}
