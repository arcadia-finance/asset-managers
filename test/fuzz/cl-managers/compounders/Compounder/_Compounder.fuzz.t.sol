/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { IUniswapV3PoolExtension } from
    "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { CompounderExtension } from "../../../../utils/extensions/CompounderExtension.sol";
import { UniswapV3Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";

/**
 * @notice Common logic needed by all "Compounder" fuzz tests.
 */
abstract contract Compounder_Fuzz_Test is Fuzz_Test, UniswapV3Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint256 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    IUniswapV3PoolExtension internal poolUniswap;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CompounderExtension internal compounder;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // Deploy test contract.
        compounder = new CompounderExtension(address(factory));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAndInitUniswapV3(uint160 sqrtPrice, uint128 liquidityPool) internal {
        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create pool.
        poolUniswap = createPoolUniV3(address(token0), address(token1), POOL_FEE, sqrtPrice, 300);

        // Create initial position.
        addLiquidityUniV3(
            poolUniswap, liquidityPool, users.liquidityProvider, BOUND_TICK_LOWER, BOUND_TICK_UPPER, false
        );
    }
}
