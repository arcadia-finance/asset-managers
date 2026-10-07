/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ArcadiaOracle } from "../../../../../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { BitPackingLib } from "../../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { Currency } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { DefaultUniswapV4AM } from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { DynamicFeeHookMock } from "../../../../utils/mocks/DynamicFeeHookMock.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import {
    FixedPoint128
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import {
    FixedPoint96
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../Fuzz.t.sol";
import { Hooks } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/Hooks.sol";
import {
    IPoolManager
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import {
    LPFeeLibrary
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/LPFeeLibrary.sol";
import { NativeTokenAM } from "../../../../../lib/accounts-v2/src/asset-modules/native-token/NativeTokenAM.sol";
import { PoolId } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import {
    ProtocolFeeLibrary
} from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/ProtocolFeeLibrary.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV4Extension } from "../../../../utils/extensions/UniswapV4Extension.sol";
import { UniswapV4Fixture } from "../../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v4/UniswapV4Fixture.f.sol";
import {
    UniswapV4HooksRegistry
} from "../../../../../lib/accounts-v2/src/asset-modules/UniswapV4/UniswapV4HooksRegistry.sol";
import { Vm } from "../../../../../lib/accounts-v2/lib/forge-std/src/Vm.sol";

/**
 * @notice Common logic needed by all "UniswapV4" fuzz tests.
 */
// forge-lint: disable-next-item(divide-before-multiply,unsafe-typecast)
abstract contract UniswapV4_Fuzz_Test is Fuzz_Test, UniswapV4Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint24 internal constant POOL_FEE = 100;
    uint24 internal constant MAX_POOL_FEE = 100_000;
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

    DynamicFeeHookMock internal dynamicFeeHook;

    // forge-lint: disable-start(mixed-case-variable)
    ArcadiaOracle internal ethOracle;
    DefaultUniswapV4AM internal defaultUniswapV4AM;
    NativeTokenAM internal nativeTokenAM;
    UniswapV4HooksRegistry internal uniswapV4HooksRegistry;
    // forge-lint: disable-end(mixed-case-variable)

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
        deployArcadiaAccounts(address(0));

        // Deploy fixture for Uniswap V3.
        UniswapV4Fixture.setUp();
        dynamicFeeHook = DynamicFeeHookMock(address(Hooks.ALL_HOOK_MASK + 1));
        deployCodeTo("DynamicFeeHookMock.sol", abi.encode(poolManager), address(dynamicFeeHook));

        // Deploy test contract.
        base =
            new UniswapV4Extension(address(positionManagerV4), address(permit2), address(poolManager), address(weth9));
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function initUniswapV4() internal returns (uint256 id) {
        id = initUniswapV4(2 ** 96, type(uint64).max, POOL_FEE, TICK_SPACING, address(0), false);
    }

    function initUniswapV4(
        uint160 sqrtPrice,
        uint128 liquidityPool,
        uint24 fee,
        int24 tickSpacing,
        address hook,
        bool native
    ) internal returns (uint256 id) {
        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (address(token0) < address(token1)) ? (token0, token1) : (token1, token0);

        addAssetsToArcadia(sqrtPrice);

        // Create pool.
        if (native) {
            deployNativeAM();
            poolKey = initializePoolV4(address(0), address(token1), uint160(sqrtPrice), hook, fee, tickSpacing);
        } else {
            poolKey = initializePoolV4(address(token0), address(token1), sqrtPrice, hook, fee, tickSpacing);
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

    // forge-lint: disable-next-item(unsafe-typecast)
    function addAssetsToArcadia(uint256 sqrtPrice) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPrice ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function givenValidPoolState(uint128 liquidityPool, PositionState memory position, uint24 protocolFee)
        internal
        view
        returns (uint128 liquidityPool_, uint24 protocolFee_)
    {
        // Given: No hook or the dynamic fee hook.
        position.pool = uint160(position.pool) % 2 == 0 ? address(0) : address(dynamicFeeHook);

        // And: Reasonable current price.
        position.sqrtPrice =
            uint160(bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3));

        // And: Pool has reasonable liquidity.
        liquidityPool_ =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        position.sqrtPrice = uint160(position.sqrtPrice);
        position.tickCurrent = TickMath.getTickAtSqrtPrice(uint160(position.sqrtPrice));
        position.poolFee = uint24(bound(position.poolFee, 0, MAX_POOL_FEE));
        position.tickSpacing = TICK_SPACING;

        // And: A protocol fee per direction.
        protocolFee_ = uint24(
            bound(protocolFee & 0xfff, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE)
                | bound(protocolFee >> 12, 0, ProtocolFeeLibrary.MAX_PROTOCOL_FEE) << 12
        );
    }

    function setPoolState(uint128 liquidityPool, PositionState memory position, uint24 protocolFee, bool native)
        internal
    {
        uint24 lpFee = position.poolFee;
        if (position.pool == address(dynamicFeeHook)) position.poolFee = LPFeeLibrary.DYNAMIC_FEE_FLAG;
        initUniswapV4(
            uint160(position.sqrtPrice), liquidityPool, position.poolFee, position.tickSpacing, position.pool, native
        );
        if (position.pool == address(dynamicFeeHook)) dynamicFeeHook.setLpFee(poolKey, lpFee);
        poolManager.setProtocolFeeController(address(this));
        poolManager.setProtocolFee(poolKey, protocolFee);
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

    function setPositionState(PositionState memory position) internal returns (uint256 amount0, uint256 amount1) {
        uint256 balance0Before;
        uint256 balance1Before;
        if (address(token0) != address(0)) balance0Before = token0.balanceOf(address(poolManager));
        if (address(token1) != address(0)) balance1Before = token1.balanceOf(address(poolManager));
        position.id = mintPositionV4(
            poolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
        if (address(token0) != address(0)) amount0 = token0.balanceOf(address(poolManager)) - balance0Before;
        if (address(token1) != address(0)) amount1 = token1.balanceOf(address(poolManager)) - balance1Before;
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function deployUniswapV4AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniswapV4HooksRegistry = new UniswapV4HooksRegistry(users.owner, address(registry), address(positionManagerV4));
        defaultUniswapV4AM = DefaultUniswapV4AM(uniswapV4HooksRegistry.DEFAULT_UNISWAP_V4_AM());

        // Add asset module to Registry.
        registry.addAssetModule(address(uniswapV4HooksRegistry));

        // Set protocol
        uniswapV4HooksRegistry.setProtocol();
        vm.stopPrank();
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function deployNativeAM() public {
        // Deploy AM
        vm.startPrank(users.owner);
        nativeTokenAM = new NativeTokenAM(users.owner, address(registry), 18);

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

    function getAmmFee() internal view returns (uint24 ammFee) {
        (,, uint24 protocolFee, uint24 lpFee) = stateView.getSlot0(poolKey.toId());
        uint16 protocolFee0 = ProtocolFeeLibrary.getZeroForOneFee(protocolFee);
        uint16 protocolFee1 = ProtocolFeeLibrary.getOneForZeroFee(protocolFee);
        ammFee = ProtocolFeeLibrary.calculateSwapFee(protocolFee0 > protocolFee1 ? protocolFee0 : protocolFee1, lpFee);
    }

    function getSwap(Vm.Log[] memory logs) internal view returns (int128 amount0, int128 amount1, uint24 fee) {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(poolManager) && logs[i].topics[0] == IPoolManager.Swap.selector
                    && logs[i].topics[1] == PoolId.unwrap(poolKey.toId())
            ) {
                (amount0, amount1,,,, fee) = abi.decode(logs[i].data, (int128, int128, uint160, uint128, int24, uint24));
            }
        }
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
}
