/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ArcadiaOracle } from "../../../../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { BitPackingLib } from "../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { DefaultUniswapV4AM } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { LiquidityAmounts } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/LiquidityAmounts.sol";
import { LiquidityAmountsExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/libraries/LiquidityAmountsExtension.sol";
import { NativeTokenAM } from "../../../../lib/accounts-v2/src/asset-modules/native-token/NativeTokenAM.sol";
import { PoolId } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolId.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import {
    PositionInfo,
    PositionInfoLibrary
} from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { IPoolManager } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/interfaces/IPoolManager.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4CompounderExtension } from "../../../utils/extensions/UniswapV4CompounderExtension.sol";
import { UniswapV4Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v4/UniswapV4Fixture.f.sol";
import { UniswapV4HooksRegistry } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/UniswapV4HooksRegistry.sol";
import { UniswapV4Logic } from "../../../../src/compounders/uniswap-v4/libraries/UniswapV4Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "UniswapV4Compounder" fuzz tests.
 */
abstract contract UniswapV4Compounder_Fuzz_Test is Fuzz_Test, UniswapV4Fixture {
    using FixedPointMathLib for uint256;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal POOL_FEE = 100;
    int24 internal TICK_SPACING = 1;

    // 5 %
    uint256 MAX_TOLERANCE = 0.05 * 1e18;
    // 4 % price diff for testing
    uint256 TOLERANCE = 0.04 * 1e18;

    // 0,5% to 11% fee on swaps.
    uint256 MIN_INITIATOR_SHARE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_FEE = 0.11 * 1e18;
    // 10 % initiator fee
    uint256 INITIATOR_SHARE = 0.1 * 1e18;
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    PoolKey internal stablePoolKey;
    PoolKey internal nativeEthPoolKey;

    address internal initiator;

    struct TestVariables {
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
    UniswapV4HooksRegistry internal uniswapV4HooksRegistry;
    UniswapV4CompounderExtension internal compounder;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error PoolManagerOnly();

    /*////////////////////////////////////////////////////////////////
                            MODIFIERS
    /////////////////////////////////////////////////////////////// */

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert PoolManagerOnly();
        _;
    }

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV4Fixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        UniswapV4Fixture.setUp();

        deployUniswapV4AM();
        deployCompounder(MAX_TOLERANCE, MAX_INITIATOR_FEE);

        // Add two stable tokens with 6 and 18 decimals.
        token0 = new ERC20Mock("Token 6d", "TOK6", 6);
        token1 = new ERC20Mock("Token 18d", "TOK18", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        vm.label({ account: address(token0), newLabel: "TOKEN0" });
        vm.label({ account: address(token1), newLabel: "TOKEN1" });

        addAssetToArcadia(address(token0), int256(10 ** MOCK_ORACLE_DECIMALS));
        addAssetToArcadia(address(token1), int256(10 ** MOCK_ORACLE_DECIMALS));

        // Create UniswapV4 pool.
        uint256 sqrtPriceX96 = compounder.getSqrtPriceX96(10 ** token1.decimals(), 10 ** token0.decimals());
        stablePoolKey = initializePoolV4(
            address(token0), address(token1), uint160(sqrtPriceX96), address(0), POOL_FEE, TICK_SPACING
        );

        // And : Compounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounder), true);

        // And : Create and set initiator details.
        initiator = createUser("initiator");
        vm.prank(initiator);
        compounder.setInitiatorInfo(TOLERANCE, INITIATOR_SHARE);

        // And : Set the initiator for the account.
        vm.prank(users.accountOwner);
        compounder.setInitiator(address(account), initiator);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
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

    function deployNativeEthPool() public {
        // Create UniswapV4 pool, native ETH has 18 decimals
        uint256 sqrtPriceX96 = compounder.getSqrtPriceX96(10 ** token1.decimals(), 1e18);
        nativeEthPoolKey =
            initializePoolV4(address(0), address(token1), uint160(sqrtPriceX96), address(0), POOL_FEE, TICK_SPACING);
    }

    function deployCompounder(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        compounder = new UniswapV4CompounderExtension(maxTolerance, maxInitiatorShare);

        // Overwrite contract addresses stored as constants in Compounder.
        bytes memory bytecode = address(compounder).code;
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x498581fF718922c3f8e6A244956aF099B2652b2b), abi.encodePacked(poolManager), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x7C5f5A4bBd8fD63184577525326123B519429bDc),
            abi.encodePacked(positionManagerV4),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71), abi.encodePacked(stateView), false
        );
        vm.etch(address(compounder), bytecode);
    }

    function givenValidBalancedState(TestVariables memory testVars, PoolKey memory poolKey)
        public
        view
        returns (TestVariables memory testVars_, bool token0HasLowestDecimals)
    {
        // Given : ticks should be in range
        (uint160 sqrtPriceX96, int24 currentTick,,) = stateView.getSlot0(poolKey.toId());

        // And : tickRange is minimum 20
        testVars.tickUpper = int24(bound(testVars.tickUpper, currentTick + 10, currentTick + type(int16).max));
        // And : Liquidity is added in 50/50
        testVars.tickLower = currentTick - (testVars.tickUpper - currentTick);

        if (PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(stablePoolKey.toId())) {
            token0HasLowestDecimals = token0.decimals() < token1.decimals() ? true : false;
        } else {
            // Doesn't matter in this case, we test for full native ETH flow only.
            token0HasLowestDecimals = false;
        }

        // And : provide liquidity in balanced way.
        uint256 maxLiquidity = getLiquidityDeltaFromAmounts(testVars.tickLower, testVars.tickUpper, sqrtPriceX96);
        // Here we set a minimum liquidity of 1e20 to avoid having unbalanced pool to quickly after fee swap.
        testVars.liquidity = uint128(bound(testVars.liquidity, 1e20, maxLiquidity));
        vm.assume(testVars.liquidity <= poolManager.getTickSpacingToMaxLiquidityPerTick(1));

        testVars_ = testVars;
    }

    function setFeeState(FeeGrowth memory feeData, PoolKey memory poolKey, uint128 liquidity)
        public
        returns (FeeGrowth memory feeData_)
    {
        // And : Amount in $ to wei.
        feeData.desiredFee0 = PoolId.unwrap(poolKey.toId()) == PoolId.unwrap(nativeEthPoolKey.toId())
            ? feeData.desiredFee0 * 1e18
            : feeData.desiredFee0 * 10 ** token0.decimals();
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

    function setState(TestVariables memory testVars, PoolKey memory poolKey) public returns (uint256 tokenId) {
        // Given : Mint initial position
        tokenId = mintPositionV4(
            poolKey,
            testVars.tickLower,
            testVars.tickUpper,
            testVars.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
    }

    function unlockCallback(bytes memory data) external onlyPoolManager returns (bytes memory results) {
        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));

        BalanceDelta delta = poolManager.swap(poolKey, params, "");

        UniswapV4Logic._processSwapDelta(delta, poolKey.currency0, poolKey.currency1);
        results = abi.encode(delta);
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

    function getFeeAmounts(uint256 id, PoolId poolId, PositionInfo info, uint128 liquidity)
        public
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            stateView.getFeeGrowthInside(poolId, info.tickLower(), info.tickUpper());

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), info.tickLower(), info.tickUpper(), bytes32(id)));

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
}
