/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { BalanceDelta } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/BalanceDelta.sol";
import { Currency } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/Currency.sol";
import { DefaultUniswapV4AM } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { LiquidityAmounts } from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/LiquidityAmounts.sol";
import { PoolKey } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
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
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal POOL_FEE = 100;
    int24 internal TICK_SPACING = 1;

    // 4 % price diff for testing
    uint256 internal TOLERANCE = 0.04 * 1e18;
    // $10
    uint256 internal COMPOUND_THRESHOLD = 10 * 1e18;
    // 10% initiator fee
    uint256 internal INITIATOR_SHARE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;
    PoolKey internal stablePoolKey;

    struct TestVariables {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        // Fee amounts in usd
        uint256 feeAmount0;
        uint256 feeAmount1;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    DefaultUniswapV4AM internal defaultUniswapV4AM;
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
        deployCompounder(COMPOUND_THRESHOLD, INITIATOR_SHARE, TOLERANCE);

        // Add two stable tokens with 6 and 18 decimals.
        token0 = new ERC20Mock("Token 6d", "TOK6", 6);
        token1 = new ERC20Mock("Token 18d", "TOK18", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

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

        // Todo : set risk params
        vm.stopPrank();
    }

    function deployCompounder(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance) public {
        vm.prank(users.owner);
        compounder = new UniswapV4CompounderExtension(compoundThreshold, initiatorShare, tolerance);

        // Overwrite contract addresses stored as constants in Compounder.
        bytes memory bytecode = address(compounder).code;
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x498581fF718922c3f8e6A244956aF099B2652b2b), abi.encodePacked(poolManager), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x7C5f5A4bBd8fD63184577525326123B519429bDc),
            abi.encodePacked(positionManagerV4),
            false
        );
        vm.etch(address(compounder), bytecode);
    }

    function givenValidBalancedState(TestVariables memory testVars)
        public
        view
        returns (TestVariables memory testVars_, bool token0HasLowestDecimals)
    {
        // Given : ticks should be in range
        (, int24 currentTick,,) = stateView.getSlot0(stablePoolKey.toId());

        // And : tickRange is minimum 20
        testVars.tickUpper = int24(bound(testVars.tickUpper, currentTick + 10, currentTick + type(int16).max));
        // And : Liquidity is added in 50/50
        testVars.tickLower = currentTick - (testVars.tickUpper - currentTick);

        token0HasLowestDecimals = token0.decimals() < token1.decimals() ? true : false;

        // And : provide liquidity in balanced way.
        testVars.liquidity = uint128(bound(testVars.liquidity, 1e6, type(uint112).max));

        // And : Position has accumulated fees (amount in USD).
        testVars.feeAmount0 = bound(testVars.feeAmount0, 100, type(uint16).max);
        testVars.feeAmount1 = bound(testVars.feeAmount1, 100, type(uint16).max);

        testVars_ = testVars;
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

        // And : Generate fees for the position
        generateFees(testVars.feeAmount0, testVars.feeAmount1, poolKey);
    }

    function generateFees(uint256 amount0ToGenerate, uint256 amount1ToGenerate, PoolKey memory poolKey) public {
        // Swap token0 for token1
        if (amount0ToGenerate > 0) {
            uint256 amount0ToSwap = ((amount0ToGenerate * (1e6 / uint24(poolKey.fee))) * 10 ** token0.decimals());

            deal(address(token0), address(this), amount0ToSwap, true);
            token0.approve(address(poolManager), amount0ToSwap);

            IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: true,
                amountSpecified: int256(amount0ToSwap),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE
            });

            bytes memory swapData = abi.encode(params, poolKey);
            // Do the swap.
            poolManager.unlock(swapData);
        }

        // Swap token1 for token0
        if (amount1ToGenerate > 0) {
            uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / uint24(poolKey.fee))) * 10 ** token1.decimals());

            deal(address(token1), address(this), amount1ToSwap, true);
            token1.approve(address(poolManager), amount1ToSwap);

            IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
                zeroForOne: false,
                amountSpecified: int256(amount1ToSwap),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE
            });

            bytes memory swapData = abi.encode(params, poolKey);
            // Do the swap.
            poolManager.unlock(swapData);
        }

        vm.stopPrank();
    }

    function unlockCallBack(bytes calldata data) external onlyPoolManager returns (bytes memory results) {
        (IPoolManager.SwapParams memory params, PoolKey memory poolKey) =
            abi.decode(data, (IPoolManager.SwapParams, PoolKey));

        BalanceDelta delta = poolManager.swap(poolKey, params, "");

        UniswapV4Logic._processBalanceDeltas(delta, poolKey.currency0, poolKey.currency1);
        results = abi.encode(delta);
    }
}
