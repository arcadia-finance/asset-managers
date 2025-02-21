/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { SwapLogicExtension } from "../../../utils/extensions/SwapLogicExtension.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "SwapLogic" fuzz tests.
 */
abstract contract SwapLogic_Fuzz_Test is Fuzz_Test, UniswapV3Fixture, SlipstreamFixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;
    int24 internal constant TICK_SPACING = 1;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    ICLPoolExtension internal poolCl;
    IUniswapV3PoolExtension internal poolUniswap;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SwapLogicExtension internal swapLogic;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, SlipstreamFixture) {
        Fuzz_Test.setUp();

        swapLogic = new SwapLogicExtension();

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        bytecode = address(swapLogic).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);
        vm.etch(address(swapLogic), bytecode);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAndInitUniswapV3(uint160 sqrtPriceX96, uint128 liquidityPool) internal {
        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // Create pool.
        poolUniswap = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPriceX96, 300);

        // Create initial position.
        addLiquidityUniV3(
            poolUniswap, liquidityPool, users.liquidityProvider, BOUND_TICK_LOWER, BOUND_TICK_UPPER, false
        );
    }

    function deployAndInitSlipstream(uint160 sqrtPriceX96, uint128 liquidityPool) internal {
        // Deploy fixture for Slipstream.
        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // Create pool.
        poolCl = createPoolCL(address(token0), address(token1), TICK_SPACING, sqrtPriceX96, 300);

        // Create initial position.
        addLiquidityCL(poolCl, liquidityPool, users.liquidityProvider, BOUND_TICK_LOWER, BOUND_TICK_UPPER, false);
    }
}
