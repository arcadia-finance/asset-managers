/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Base_Test } from "../../../../lib/accounts-v2/test/Base.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3Extension } from "../../../utils/extensions/RebalancerUniswapV3Extension.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV3AMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { UniswapV3AMFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/UniswapV3AMFixture.f.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV3" fuzz tests.
 */
abstract contract RebalancerUniswapV3_Fuzz_Test is Fuzz_Test, UniswapV3Fixture, UniswapV3AMFixture {
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

    RebalancerUniswapV3Extension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, Base_Test) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts();

        // Deploy fixture for Uniswap V3.
        UniswapV3Fixture.setUp();

        // Deploy test contract.
        rebalancer = new RebalancerUniswapV3Extension(
            address(factory),
            MAX_TOLERANCE,
            MAX_FEE,
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

    function initUniswapV3() internal returns (uint256 id) {
        id = initUniswapV3(2 ** 96, type(uint64).max, POOL_FEE);
    }

    function initUniswapV3(uint160 sqrtPrice, uint128 liquidityPool, uint24 poolFee) internal returns (uint256 id) {
        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPrice);

        // Create pool.
        poolUniswap = createPoolUniV3(address(token0), address(token1), poolFee, sqrtPrice, 300);

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

    function addAssetsToArcadia(uint256 sqrtPrice) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPrice ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function givenValidPoolState(uint128 liquidityPool, PositionState memory position)
        internal
        view
        returns (uint128 liquidityPool_)
    {
        // Given: Reasonable current price.
        position.sqrtPrice =
            uint160(bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));

        // And: Pool has reasonable liquidity.
        liquidityPool_ =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        position.sqrtPrice = uint160(position.sqrtPrice);
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice));
        position.fee = POOL_FEE;
    }

    function setPoolState(uint128 liquidityPool, PositionState memory position) internal {
        initUniswapV3(uint160(position.sqrtPrice), liquidityPool, position.fee);
        position.pool = address(poolUniswap);
        position.tickSpacing = poolUniswap.tickSpacing();
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
    }

    function givenValidPositionState(PositionState memory position) internal {
        int24 tickSpacing = position.tickSpacing;
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, poolUniswap.liquidity() / 1e3));
    }

    function setPositionState(PositionState memory position) internal {
        (position.id,,) = addLiquidityUniV3(
            poolUniswap, position.liquidity, users.liquidityProvider, position.tickLower, position.tickUpper, false
        );
        (,,,,,,, position.liquidity,,,,) = nonfungiblePositionManager.positions(position.id);
    }

    function deployUniswapV3AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniV3AM = new UniswapV3AMExtension(address(registry), address(nonfungiblePositionManager));
        registry.addAssetModule(address(uniV3AM));
        uniV3AM.setProtocol();
        vm.stopPrank();

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3AMExtension.
        bytecode = address(uniV3AM).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);
        vm.etch(address(uniV3AM), bytecode);
    }
}
