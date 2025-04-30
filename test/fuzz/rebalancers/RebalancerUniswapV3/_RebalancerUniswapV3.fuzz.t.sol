/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3Extension } from "../../../utils/extensions/RebalancerUniswapV3Extension.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV3" fuzz tests.
 */
abstract contract RebalancerUniswapV3_Fuzz_Test is Fuzz_Test, UniswapV3Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint256 internal constant MAX_INITIATOR_FEE = 0.01 * 1e18;
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

    RebalancerUniswapV3Extension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        // Deploy test contract.
        rebalancer = new RebalancerUniswapV3Extension(
            address(factory),
            MAX_TOLERANCE,
            MAX_INITIATOR_FEE,
            MIN_LIQUIDITY_RATIO,
            address(nonfungiblePositionManager),
            address(uniswapV3Factory)
        );

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = address(rebalancer).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Store overwritten bytecode.
        vm.etch(address(rebalancer), bytecode);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function addAssetsToArcadia(uint256 sqrtPriceX96) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPriceX96 ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function deployAndInitUniswapV3(uint160 sqrtPriceX96, uint128 liquidityPool, uint24 poolFee)
        internal
        returns (uint256 id)
    {
        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPriceX96);

        // Create pool.
        poolUniswap = createPoolUniV3(address(token0), address(token1), poolFee, sqrtPriceX96, 300);

        // Create initial position.
        int24 tickSpacing = poolUniswap.tickSpacing();
        (id,,) = addLiquidityUniV3(
            poolUniswap,
            liquidityPool,
            users.liquidityProvider,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            false
        );
    }

    function givenValidPosition(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position
    ) internal {
        // Given: Reasonable current price.
        position.sqrtPriceX96 =
            uint160(bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));

        // And: A valid pool.
        // And: Pool has reasonable liquidity.
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool, POOL_FEE);
        position.sqrtPriceX96 = uint160(position.sqrtPriceX96);
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPriceX96));
        position.pool = address(poolUniswap);
        position.fee = POOL_FEE;
        int24 tickSpacing = poolUniswap.tickSpacing();
        position.tickSpacing = tickSpacing;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);

        // And: A valid position.
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
        (position.id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        initiatorParams.oldId = uint96(position.id);
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(initiatorParams.oldId);
    }
}
