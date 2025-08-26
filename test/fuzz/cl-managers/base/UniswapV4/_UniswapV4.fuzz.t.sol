/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ArcadiaOracle } from "../../../../../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { BitPackingLib } from "../../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { Currency } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { DefaultUniswapV4AM } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FixedPoint128 } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { IPoolManager } from
    "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { NativeTokenAM } from "../../../../../lib/accounts-v2/src/asset-modules/native-token/NativeTokenAM.sol";
import { PoolId } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4Extension } from "../../../../utils/extensions/UniswapV4Extension.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV4Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v4/UniswapV4Fixture.f.sol";
import { UniswapV4HooksRegistry } from
    "../../../../../lib/accounts-v2/src/asset-modules/UniswapV4/UniswapV4HooksRegistry.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "UniswapV4" fuzz tests.
 */
abstract contract UniswapV4_Fuzz_Test is Fuzz_Test, UniswapV4Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;
    int24 internal constant TICK_SPACING = 1;

    uint256 internal constant MAX_TOLERANCE = 0.02 * 1e18;
    uint64 internal constant MAX_FEE = 0.01 * 1e18;
    uint256 internal constant MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    PoolKey internal poolKey;

    ArcadiaOracle internal ethOracle;
    DefaultUniswapV4AM internal defaultUniswapV4AM;
    NativeTokenAM internal nativeTokenAM;
    UniswapV4HooksRegistry internal uniswapV4HooksRegistry;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    UniswapV4Extension internal base;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV4Fixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts();

        // Deploy fixture for Uniswap V3.
        UniswapV4Fixture.setUp();

        // Deploy test contract.
        base =
            new UniswapV4Extension(address(positionManagerV4), address(permit2), address(poolManager), address(weth9));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function initUniswapV4() internal returns (uint256 id) {
        id = initUniswapV4(2 ** 96, type(uint64).max, POOL_FEE, TICK_SPACING, false);
    }

    function initUniswapV4(uint160 sqrtPrice, uint128 liquidityPool, uint24 fee, int24 tickSpacing, bool native)
        internal
        returns (uint256 id)
    {
        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPrice);

        // Create pool.
        if (native) {
            deployNativeAM();
            poolKey = initializePoolV4(address(0), address(token1), uint160(sqrtPrice), address(0), fee, tickSpacing);
        } else {
            poolKey = initializePoolV4(address(token0), address(token1), sqrtPrice, address(0), fee, tickSpacing);
        }

        // Create initial position.
        id = mintPositionV4(
            poolKey,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            liquidityPool,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
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
        // Given: No hook is set.
        position.pool = address(0);

        // And: Reasonable current price.
        position.sqrtPrice =
            uint160(bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));

        // And: Pool has reasonable liquidity.
        liquidityPool_ =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        position.sqrtPrice = uint160(position.sqrtPrice);
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice));
        position.fee = POOL_FEE;
        position.tickSpacing = TICK_SPACING;
    }

    function setPoolState(uint128 liquidityPool, PositionState memory position, bool native) internal {
        initUniswapV4(uint160(position.sqrtPrice), liquidityPool, position.fee, position.tickSpacing, native);
        position.tokens = new address[](2);
        position.tokens[0] = native ? address(0) : address(token0);
        position.tokens[1] = address(token1);
    }

    function givenValidPositionState(PositionState memory position) internal view {
        int24 tickSpacing = position.tickSpacing;
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 2 * tickSpacing));
        position.tickLower = position.tickLower / tickSpacing * tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickLower + 2 * tickSpacing, BOUND_TICK_UPPER));
        position.tickUpper = position.tickUpper / tickSpacing * tickSpacing;
        position.liquidity = uint128(bound(position.liquidity, 1e6, stateView.getLiquidity(poolKey.toId()) / 1e3));
    }

    function setPositionState(PositionState memory position) internal {
        position.id = mintPositionV4(
            poolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
    }

    function deployUniswapV4AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniswapV4HooksRegistry = new UniswapV4HooksRegistry(address(registry), address(positionManagerV4));
        defaultUniswapV4AM = DefaultUniswapV4AM(uniswapV4HooksRegistry.DEFAULT_UNISWAP_V4_AM());

        // Add asset module to Registry.
        registry.addAssetModule(address(uniswapV4HooksRegistry));

        // Set protocol
        uniswapV4HooksRegistry.setProtocol();
        vm.stopPrank();
    }

    function deployNativeAM() public {
        // Deploy AM
        vm.startPrank(users.owner);
        nativeTokenAM = new NativeTokenAM(address(registry), 18);

        // Add AM to registry
        registry.addAssetModule(address(nativeTokenAM));

        // Init and add ETH oracle
        ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
        vm.startPrank(chainlinkOM.owner());
        chainlinkOM.addOracle(address(ethOracle), "ETH", "USD", 2 days);

        uint80[] memory oracleEthToUsdArr = new uint80[](1);
        oracleEthToUsdArr[0] = uint80(chainlinkOM.oracleToOracleId(address(ethOracle)));

        vm.startPrank(registry.owner());
        erc20AM.addAsset(address(weth9), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        nativeTokenAM.addAsset(address(0), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        vm.stopPrank();
    }

    function generateFees(uint256 amount0, uint256 amount1) public {
        // Calculate expected feeGrowth difference in order to obtain desired fee
        // (fee * Q128) / liquidity = diff in Q128.
        // As fee amount is calculated based on deducting feeGrowthOutside from feeGrowthGlobal,
        // no need to test with fuzzed feeGrowthOutside values as no risk of potential rounding errors (we're not testing UniV4 contracts).
        uint256 deltaFeeGrowth0X128 = amount0 * FixedPoint128.Q128 / stateView.getLiquidity(poolKey.toId());
        uint256 deltaFeeGrowth1X128 = amount1 * FixedPoint128.Q128 / stateView.getLiquidity(poolKey.toId());

        // And : Set state
        poolManager.setFeeGrowthGlobal(poolKey.toId(), deltaFeeGrowth0X128, deltaFeeGrowth1X128);

        // And : Mint fee to the pool
        Currency.unwrap(poolKey.currency0) == address(0)
            ? vm.deal(address(poolManager), address(poolManager).balance + amount0)
            : token0.mint(address(poolManager), amount0);

        token1.mint(address(poolManager), amount1);
    }

    function getFeeAmounts(uint256 id) internal view returns (uint256 amount0, uint256 amount1) {
        PositionInfo info = positionManagerV4.positionInfo(id);

        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            stateView.getFeeGrowthInside(poolKey.toId(), info.tickLower(), info.tickUpper());

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), info.tickLower(), info.tickUpper(), bytes32(id)));

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            stateView.getPositionInfo(poolKey.toId(), positionId);

        // Calculate accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in PositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 = FullMath.mulDiv(
                feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128,
                positionManagerV4.getPositionLiquidity(id),
                FixedPoint128.Q128
            );
            amount1 = FullMath.mulDiv(
                feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128,
                positionManagerV4.getPositionLiquidity(id),
                FixedPoint128.Q128
            );
        }
    }
}
