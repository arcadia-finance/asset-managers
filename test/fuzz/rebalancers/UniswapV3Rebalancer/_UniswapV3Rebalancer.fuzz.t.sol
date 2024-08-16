/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_Test } from "../../../../lib/accounts-v2/test/Base.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { QuoterV2Fixture } from "../../../utils/fixtures/uniswap-v3/QuoterV2Fixture.f.sol";
import { SwapRouter02Fixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/SwapRouter02Fixture.f.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3AMFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/UniswapV3AMFixture.f.sol";
import { UniswapV3AMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { UniswapV3RebalancerExtension } from "../../../utils/extensions/UniswapV3RebalancerExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "UniswapV3Rebalancer" fuzz tests.
 */
abstract contract UniswapV3Rebalancer_Fuzz_Test is
    Fuzz_Test,
    UniswapV3Fixture,
    UniswapV3AMFixture,
    SwapRouter02Fixture,
    QuoterV2Fixture
{
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint128;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal POOL_FEE = 100;

    // 4 % price diff for testing
    uint256 internal TOLERANCE = 0.04 * 1e18;

    // 2 % liquidity treshold for rebalancer
    uint256 internal LIQUIDITY_TRESHOLD = 0.02 * 1e18;

    // Minimum liquidity amount to use for tests
    uint256 internal MIN_LIQUIDITY = 0.005 * 1e18;

    int24 internal MIN_TICK_SPACING = 10;
    int24 internal INIT_LP_TICK_RANGE = 20_000;

    // TODO : 10% initiator fee
    uint256 internal INITIATOR_SHARE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    IUniswapV3PoolExtension internal uniV3Pool;

    struct InitVariables {
        int24 tickLower;
        int24 tickUpper;
        uint256 initToken0Amount;
        uint256 initToken1Amount;
        uint8 token0Decimals;
        uint8 token1Decimals;
        uint256 priceToken0;
        uint256 priceToken1;
    }

    struct LpVariables {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    UniswapV3RebalancerExtension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, Base_Test) {
        Fuzz_Test.setUp();

        UniswapV3Fixture.setUp();
        SwapRouter02Fixture.deploySwapRouter02(
            address(0), address(uniswapV3Factory), address(nonfungiblePositionManager), address(weth9)
        );
        QuoterV2Fixture.deployQuoterV2(address(uniswapV3Factory), address(weth9));

        deployUniswapV3AM();
        deployRebalancer(TOLERANCE, LIQUIDITY_TRESHOLD);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
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

    function deployRebalancer(uint256 tolerance, uint256 liquidityTreshold) public {
        vm.prank(users.owner);
        rebalancer = new UniswapV3RebalancerExtension(tolerance, liquidityTreshold);

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(rebalancer).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in Rebalancer.
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
        vm.etch(address(rebalancer), bytecode);
    }

    function initPoolAndCreatePositionWithFees(InitVariables memory initVars, LpVariables memory lpVars)
        public
        returns (InitVariables memory initVars_, LpVariables memory lpVars_, uint256 tokenId)
    {
        // Given : Initialize a uniswapV3 pool
        initVars_ = initPool(initVars);

        // And : get valid position vars
        lpVars_ = givenValidTestVars(lpVars, initVars);

        // And : Create new position and generate fees
        tokenId = createNewPositionAndGenerateFees(lpVars_, uniV3Pool);
    }

    function initPool(InitVariables memory initVars) public returns (InitVariables memory initVars_) {
        // Given : Tokens have min 6 and max 18 decimals
        initVars.token0Decimals = uint8(bound(initVars.token0Decimals, 6, 18));
        initVars.token1Decimals = uint8(bound(initVars.token1Decimals, 6, 18));

        uint256 sqrtPriceX96;
        {
            // And : Avoid too big price diffs, this should not have impact on test objective
            initVars.priceToken0 = bound(initVars.priceToken0, 1, type(uint256).max / 10 ** 64);
            initVars.priceToken1 = bound(initVars.priceToken1, 1, type(uint256).max / 10 ** 64);
            // And : Cast to uint160 will overflow, not realistic.
            vm.assume(initVars.priceToken0 / initVars.priceToken1 < 2 ** 128);
            // sqrtPriceX96 must be within ranges, or TickMath reverts.
            uint256 priceXd28 = initVars.priceToken0 * 1e28 / initVars.priceToken1;
            uint256 sqrtPriceXd14 = FixedPointMathLib.sqrt(priceXd28);
            sqrtPriceX96 = sqrtPriceXd14 * 2 ** 96 / 1e14;
            vm.assume(sqrtPriceX96 >= 4_295_128_739);
            vm.assume(sqrtPriceX96 <= 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342);
        }

        // And : add new pool tokens to Arcadia
        token0 = new ERC20Mock("TokenA", "TOKA", initVars.token0Decimals);
        token1 = new ERC20Mock("TokenB", "TOKB", initVars.token1Decimals);
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
            (initVars.token0Decimals, initVars.token1Decimals) = (initVars.token0Decimals, initVars.token1Decimals);
            (initVars.priceToken0, initVars.priceToken1) = (initVars.priceToken1, initVars.priceToken0);
        }

        addAssetToArcadia(address(token0), int256(initVars.priceToken0));
        addAssetToArcadia(address(token1), int256(initVars.priceToken1));

        // And : Create new uniV3 pool
        uniV3Pool = createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(sqrtPriceX96), 300);

        int24 currentTick = uniV3Pool.getCurrentTick();

        // And : Supply an initial LP position around a specific amount of ticks
        initVars.tickLower = currentTick - (INIT_LP_TICK_RANGE / 2);
        initVars.tickUpper = currentTick + (INIT_LP_TICK_RANGE / 2) - 1;

        // And : Supply a minimal amount of tokens such that the next LP that we will deposit would not be too small
        // compared to the value of the initial one.
        initVars.initToken0Amount = bound(initVars.initToken0Amount, 1e18, type(uint80).max);
        initVars.initToken1Amount = bound(initVars.initToken1Amount, 1e18, type(uint80).max);

        // And : Mint initial position
        (, initVars.initToken0Amount, initVars.initToken1Amount) = addLiquidityUniV3(
            uniV3Pool,
            initVars.initToken0Amount,
            initVars.initToken1Amount,
            users.liquidityProvider,
            initVars.tickLower,
            initVars.tickUpper,
            true
        );

        initVars_ = initVars;
    }

    function givenValidTestVars(LpVariables memory lpVars, InitVariables memory initVars)
        public
        returns (LpVariables memory lpVars_)
    {
        // Given : Liquidity for new position is in limits
        uint128 currentLiquidity = uniV3Pool.liquidity();
        uint256 minLiquidity = currentLiquidity.mulDivDown(MIN_LIQUIDITY, 1e18);
        uint256 maxLiquidity = currentLiquidity.mulDivDown(LIQUIDITY_TRESHOLD, 1e18);
        lpVars.liquidity = uint128(bound(lpVars.liquidity, minLiquidity, maxLiquidity));

        // And : Lower and upper ticks of the position are within the initial liquidity range
        int24 currentTick = uniV3Pool.getCurrentTick();

        lpVars.tickLower = int24(bound(lpVars.tickLower, initVars.tickLower, currentTick - MIN_TICK_SPACING));
        lpVars.tickUpper = int24(bound(lpVars.tickUpper, currentTick + MIN_TICK_SPACING, initVars.tickUpper - 1));

        lpVars_ = lpVars;
    }

    function createNewPositionAndGenerateFees(LpVariables memory lpVars, IUniswapV3PoolExtension pool)
        public
        returns (uint256 tokenId)
    {
        // Given : Calculate amount of token0 and token1 needed to deposit specific liquidity
        (uint160 sqrtPrice,,,,,,) = uniV3Pool.slot0();
        (lpVars.amount0, lpVars.amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice,
            TickMath.getSqrtRatioAtTick(lpVars.tickLower),
            TickMath.getSqrtRatioAtTick(lpVars.tickUpper),
            lpVars.liquidity
        );

        // And : assume the amounts are at least 1000 so that in generateFees(), using those amounts, it indeed generates a positive fee
        vm.assume(lpVars.amount0 > 1000 && lpVars.amount1 > 1000);

        // Given : Mint new position
        (tokenId,,) = addLiquidityUniV3(
            pool, lpVars.amount0, lpVars.amount1, users.liquidityProvider, lpVars.tickLower, lpVars.tickUpper, true
        );

        // And : Generate fees for the position
        // We use the amount0 and amount1 of the latest LP, as it should be smaller than the initial LP,
        // and not have too big impact on price. The fee amount is not relevant for testing.
        generateFees(lpVars);
    }

    function generateFees(LpVariables memory lpVars) public {
        vm.startPrank(users.liquidityProvider);
        ISwapRouter02.ExactInputSingleParams memory exactInputParams;
        // Swap token0 for token1
        uint256 amount0ToSwap = lpVars.amount0;

        deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

        token0.approve(address(swapRouter), amount0ToSwap);

        exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: uniV3Pool.fee(),
            recipient: users.liquidityProvider,
            amountIn: amount0ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        // Swap token1 for token0
        uint256 amount1ToSwap = lpVars.amount1;

        deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
        token1.approve(address(swapRouter), amount1ToSwap);

        exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: uniV3Pool.fee(),
            recipient: users.liquidityProvider,
            amountIn: amount1ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        vm.stopPrank();
    }
}