/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ArcadiaOracle } from "../../../../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { BitPackingLib } from "../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { DefaultUniswapV4AM } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPoint96 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint96.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IPoolManager } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
import { LiquidityAmountsExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/libraries/LiquidityAmountsExtension.sol";
import { NativeTokenAM } from "../../../../lib/accounts-v2/src/asset-modules/native-token/NativeTokenAM.sol";
import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    PositionInfoLibrary,
    PositionInfo
} from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { RebalancerUniswapV4Extension } from "../../../utils/extensions/RebalancerUniswapV4Extension.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";
import { UniswapV4Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v4/UniswapV4Fixture.f.sol";
import { UniswapV4HooksRegistry } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/UniswapV4HooksRegistry.sol";
import { UniswapV4Logic } from "../../../../src/rebalancers/libraries/uniswap-v4/UniswapV4Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV4" fuzz tests.
 */
abstract contract RebalancerUniswapV4_Fuzz_Test is Fuzz_Test, UniswapV4Fixture {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint128;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal constant POOL_FEE = 100;
    int24 internal constant TICK_SPACING = 1;

    // 2 % price diff for testing.
    uint256 internal MAX_TOLERANCE = 0.02 * 1e18;

    // 0,5% to 1% fee on swaps.
    uint256 MIN_INITIATOR_FEE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_FEE = 0.01 * 1e18;

    // Minimum liquidity ratio for minted position, 0,005%
    uint256 internal MIN_LIQUIDITY = 0.005 * 1e18;

    // Max liquidity ratio of minted position, 0.02%
    uint256 internal LIQUIDITY_TRESHOLD = 0.02 * 1e18;

    int24 internal MIN_TICK_SPACING = 10;
    int24 internal INIT_LP_TICK_RANGE = 20_000;

    // Max slippage of 1% (for testing purposes).
    uint256 internal MIN_LIQUIDITY_RATIO = 0.99 * 1e18;

    address public constant WETH = 0x4200000000000000000000000000000000000006;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    PoolKey internal v4PoolKey;
    PoolKey internal nativeEthPoolKey;

    // If set to "true" during tests, will enable to mock high tolerance
    bool public increaseTolerance;

    struct InitVariables {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint256 priceToken0;
        uint256 priceToken1;
        uint256 decimalsDiff;
        address initiator;
        uint256 tolerance;
        uint256 fee;
    }

    struct LpVariables {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
    }

    struct FeeGrowth {
        uint256 desiredFee0;
        uint256 desiredFee1;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    ArcadiaOracle internal ethOracle;
    DefaultUniswapV4AM internal defaultUniswapV4AM;
    NativeTokenAM internal nativeTokenAM;
    RebalancerUniswapV4Extension internal rebalancer;
    UniswapV4HooksRegistry internal uniswapV4HooksRegistry;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV4Fixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts();

        UniswapV4Fixture.setUp();

        deployUniswapV4AM();
        deployUniswapV4Rebalancer(MAX_TOLERANCE, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);
    }

    /* ///////////////////////////////////////////////////////////////
                              HELPERS
    /////////////////////////////////////////////////////////////// */
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
        nativeTokenAM = new NativeTokenAM(address(registry));

        // Add AM to registry
        registry.addAssetModule(address(nativeTokenAM));

        // Init and add ETH oracle
        ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
        vm.startPrank(chainlinkOM.owner());
        chainlinkOM.addOracle(address(ethOracle), "ETH", "USD", 2 days);

        uint80[] memory oracleEthToUsdArr = new uint80[](1);
        oracleEthToUsdArr[0] = uint80(chainlinkOM.oracleToOracleId(address(ethOracle)));

        vm.startPrank(registry.owner());
        nativeTokenAM.addAsset(address(0), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));

        vm.stopPrank();
    }

    function deployNativeEthPool(uint128 liquidity, uint24 fee, int24 tickSpacing, address hook)
        public
        returns (uint256 tokenId, uint256 sqrtPriceX96)
    {
        // Add a token 1 with fixed 18 decimals (we dont test for decimals in this flow).
        token1 = new ERC20Mock("TokenB", "TOKB", 18);
        vm.label({ account: address(token1), newLabel: "TOKENB" });
        addAssetToArcadia(address(token1), int256(10 ** MOCK_ORACLE_DECIMALS));

        // Create UniswapV4 pool, native ETH has 18 decimals
        sqrtPriceX96 = getSqrtPriceX96(10 ** token1.decimals(), 1e18);
        nativeEthPoolKey = initializePoolV4(address(0), address(token1), uint160(sqrtPriceX96), hook, fee, tickSpacing);

        // Add liquidity.
        tokenId = mintPositionV4(
            nativeEthPoolKey,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
    }

    function deployUniswapV4Rebalancer(uint256 maxTolerance, uint256 maxInitiatorFee) public {
        rebalancer = new RebalancerUniswapV4Extension(maxTolerance, maxInitiatorFee, MIN_LIQUIDITY_RATIO);
        // Overwrite Arcadia contract addresses, stored as constants in Rebalancer.
        bytes memory bytecode = address(rebalancer).code;

        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x498581fF718922c3f8e6A244956aF099B2652b2b),
            abi.encodePacked(address(poolManager)),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x7C5f5A4bBd8fD63184577525326123B519429bDc),
            abi.encodePacked((address(positionManagerV4))),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71),
            abi.encodePacked((address(stateView))),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x000000000022D473030F116dDEE9F6B43aC78BA3),
            abi.encodePacked((address(permit2))),
            false
        );

        // Store overwritten bytecode.
        vm.etch(address(rebalancer), bytecode);
        // Store the weth bytecode to the weth address.
        vm.etch(0x4200000000000000000000000000000000000006, address(weth9).code);
    }

    // From UniV4-core tests
    function getLiquidityDeltaFromAmounts(int24 tickLower, int24 tickUpper, uint160 sqrtPriceX96)
        public
        pure
        returns (uint256 liquidityMaxByAmount)
    {
        // First get the maximum amount0 and maximum amount1 that can be deposited at this range.
        (uint256 maxAmount0, uint256 maxAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(type(int128).max)
        );

        // Compare the max amounts (defined by the range of the position) to the max amount constrained by the type container.
        // The true maximum should be the minimum of the two.
        // (ie If the position range allows a deposit of more then int128.max in any token, then here we cap it at int128.max.)
        uint256 amount0 = uint256(type(uint128).max / 2);
        uint256 amount1 = uint256(type(uint128).max / 2);

        maxAmount0 = maxAmount0 > amount0 ? amount0 : maxAmount0;
        maxAmount1 = maxAmount1 > amount1 ? amount1 : maxAmount1;

        liquidityMaxByAmount = LiquidityAmountsExtension.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            maxAmount0,
            maxAmount1
        );
    }

    function setInitiatorInfo(address initiator, uint256 tolerance, uint256 fee)
        public
        returns (uint256 tolerance_, uint256 fee_)
    {
        // Too low tolerance for testing will make tests reverts too quickly with unbalancedPool()
        tolerance = bound(tolerance, 0.0001 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0, MAX_INITIATOR_FEE);
        if (increaseTolerance == true) {
            tolerance = rebalancer.MAX_TOLERANCE();
        }

        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);

        return (tolerance, fee);
    }

    function setFeeState(FeeGrowth memory feeData, PoolKey memory poolKey, uint128 liquidity)
        public
        returns (FeeGrowth memory feeData_)
    {
        // And : Amount in $ to wei.
        feeData.desiredFee0 = PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(nativeEthPoolKey.toId())
            ? feeData.desiredFee0 * 1e18
            : feeData.desiredFee0 = feeData.desiredFee0 * 10 ** token0.decimals();
        feeData.desiredFee1 = feeData.desiredFee1 * 10 ** token1.decimals();

        // And : Calculate expected feeGrowth difference in order to obtain desired fee
        // (fee * Q128) / liquidity = diff in Q128.
        // As fee amount is calculated based on deducting feeGrowthOutside from feeGrowthGlobal,
        // no need to test with fuzzed feeGrowthOutside values as no risk of potential rounding errors (we're not testing UniV4 contracts).
        uint256 feeGrowthDiff0X128 = feeData.desiredFee0.mulDivDown(FixedPoint128.Q128, liquidity);
        feeData.feeGrowthGlobal0X128 = feeGrowthDiff0X128;

        uint256 feeGrowthDiff1X128 = feeData.desiredFee1.mulDivDown(FixedPoint128.Q128, liquidity);
        feeData.feeGrowthGlobal1X128 = feeGrowthDiff1X128;

        // And : Set state
        poolManager.setFeeGrowthGlobal(poolKey.toId(), feeData.feeGrowthGlobal0X128, feeData.feeGrowthGlobal1X128);

        // And : Mint fee to the pool
        PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(nativeEthPoolKey.toId())
            ? vm.deal(address(poolManager), address(poolManager).balance + feeData.desiredFee0)
            : token0.mint(address(poolManager), feeData.desiredFee0);

        token1.mint(address(poolManager), feeData.desiredFee1);

        feeData_ = feeData;
    }

    function addAssetsToArcadia(uint256 sqrtPriceX96) internal {
        uint256 price0 = FullMath.mulDiv(1e18, sqrtPriceX96 ** 2, FixedPoint96.Q96 ** 2);
        uint256 price1 = 1e18;

        addAssetToArcadia(address(token0), int256(price0));
        addAssetToArcadia(address(token1), int256(price1));
    }

    function initPoolAndAddLiquidity(
        uint160 sqrtPriceX96,
        uint128 liquidity,
        uint24 fee,
        int24 tickSpacing,
        address hook
    ) public returns (uint256 tokenId) {
        // Given : add new pool tokens to Arcadia
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);

        // Add assets to the protocol.
        addAssetsToArcadia(sqrtPriceX96);

        // Init Pool.
        v4PoolKey = initializePoolV4(address(token0), address(token1), sqrtPriceX96, hook, fee, tickSpacing);

        // Add liquidity.
        tokenId = mintPositionV4(
            v4PoolKey,
            BOUND_TICK_LOWER / tickSpacing * tickSpacing,
            BOUND_TICK_UPPER / tickSpacing * tickSpacing,
            liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
    }

    function unlockCallback(bytes calldata data) external payable returns (bytes memory results) {
        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));
        BalanceDelta delta = poolManager.swap(poolKey, params, "");
        UniswapV4Logic._processSwapDelta(delta, poolKey.currency0, poolKey.currency1);
        results = abi.encode(delta);
    }

    function getFeeAmounts(uint256 id, PoolId poolId, int24 tickLower, int24 tickUpper, uint128 liquidity)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            stateView.getFeeGrowthInside(poolId, tickLower, tickUpper);

        bytes32 positionId = keccak256(abi.encodePacked(address(positionManagerV4), tickLower, tickUpper, bytes32(id)));

        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128) =
            stateView.getPositionInfo(poolId, positionId);

        // Calculate accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in PositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 =
                FullMath.mulDiv(feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
            amount1 =
                FullMath.mulDiv(feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
        }
    }

    function getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) public pure returns (uint160 sqrtPriceX96) {
        if (priceToken1 == 0) return TickMath.MAX_SQRT_PRICE;

        // Both priceTokens have 18 decimals precision and result of division should have 28 decimals precision.
        // -> multiply by 1e28
        // priceXd28 will overflow if priceToken0 is greater than 1.158e+49.
        // For WBTC (which only has 8 decimals) this would require a bitcoin price greater than 115 792 089 237 316 198 989 824 USD/BTC.
        uint256 priceXd28 = priceToken0.mulDivDown(1e28, priceToken1);
        // Square root of a number with 28 decimals precision has 14 decimals precision.
        uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);

        // Change sqrtPrice from a decimal fixed point number with 14 digits to a binary fixed point number with 96 digits.
        // Unsafe cast: Cast will only overflow when priceToken0/priceToken1 >= 2^128.
        sqrtPriceX96 = uint160((sqrtPriceXd14 << FixedPoint96.RESOLUTION) / 1e14);
    }
}
