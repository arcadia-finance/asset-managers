/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Base_Test } from "../../../../lib/accounts-v2/test/Base.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { IUniswapV3PoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { QuoterV2Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/QuoterV2Fixture.f.sol";
import { SwapRouter02Fixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/SwapRouter02Fixture.f.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3AMFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/UniswapV3AMFixture.f.sol";
import { UniswapV3AMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3CompounderExtension } from "../../../utils/extensions/UniswapV3CompounderExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "UniswapV3Compounder" fuzz tests.
 */
abstract contract UniswapV3Compounder_Fuzz_Test is
    Fuzz_Test,
    UniswapV3Fixture,
    UniswapV3AMFixture,
    SwapRouter02Fixture,
    QuoterV2Fixture
{
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal POOL_FEE = 100;

    // 5 %
    uint256 MAX_TOLERANCE = 0.05 * 1e18;
    // 4 % price diff for testing
    uint256 TOLERANCE = 0.04 * 1e18;

    // 0,5% to 11% fee on swaps.
    uint256 MIN_INITIATOR_SHARE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_SHARE = 0.11 * 1e18;
    // 10 % initiator fee
    uint256 INITIATOR_SHARE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    IUniswapV3PoolExtension internal usdStablePool;

    address internal initiator;

    struct TestVariables {
        int24 tickLower;
        int24 tickUpper;
        uint112 amountToken0;
        uint112 amountToken1;
        // Fee amounts in usd
        uint256 feeAmount0;
        uint256 feeAmount1;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    UniswapV3CompounderExtension internal compounder;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, Base_Test) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        UniswapV3Fixture.setUp();
        SwapRouter02Fixture.deploySwapRouter02(
            address(0), address(uniswapV3Factory), address(nonfungiblePositionManager), address(weth9)
        );
        QuoterV2Fixture.deployQuoterV2(address(uniswapV3Factory), address(weth9));

        deployUniswapV3AM();
        deployCompounder(MAX_TOLERANCE, MAX_INITIATOR_SHARE);

        // Add two stable tokens with 6 and 18 decimals.
        token0 = new ERC20Mock("Token 6d", "TOK6", 6);
        token1 = new ERC20Mock("Token 18d", "TOK18", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** MOCK_ORACLE_DECIMALS));
        addAssetToArcadia(address(token1), int256(10 ** MOCK_ORACLE_DECIMALS));

        // Create UniswapV3 pool.
        uint256 sqrtPriceX96 = compounder.getSqrtPriceX96(10 ** token1.decimals(), 10 ** token0.decimals());
        usdStablePool = createPoolUniV3(address(token0), address(token1), POOL_FEE, uint160(sqrtPriceX96), 300);

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

    function deployCompounder(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        compounder = new UniswapV3CompounderExtension(maxTolerance, maxInitiatorShare);

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(compounder).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in Compounder.
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
        vm.etch(address(compounder), bytecode);
    }

    function givenValidBalancedState(TestVariables memory testVars)
        public
        view
        returns (TestVariables memory testVars_, bool token0HasLowestDecimals)
    {
        // Given : ticks should be in range
        int24 currentTick = usdStablePool.getCurrentTick();

        // And : tickRange is minimum 20
        testVars.tickUpper = int24(bound(testVars.tickUpper, currentTick + 10, currentTick + type(int16).max));
        // And : Liquidity is added in 50/50
        testVars.tickLower = currentTick - (testVars.tickUpper - currentTick);

        token0HasLowestDecimals = token0.decimals() < token1.decimals() ? true : false;

        // And : provide liquidity in balanced way.
        // Amount has no impact
        testVars.amountToken0 = token0HasLowestDecimals
            ? type(uint112).max / uint112((10 ** (token1.decimals() - token0.decimals())))
            : type(uint112).max;
        testVars.amountToken1 = token0HasLowestDecimals
            ? type(uint112).max
            : type(uint112).max / uint112((10 ** (token0.decimals() - token1.decimals())));

        // And : Position has accumulated fees (amount in USD)
        testVars.feeAmount0 = bound(testVars.feeAmount0, 100, type(uint16).max);
        testVars.feeAmount1 = bound(testVars.feeAmount1, 100, type(uint16).max);

        testVars_ = testVars;
    }

    function setState(TestVariables memory testVars, IUniswapV3PoolExtension pool) public returns (uint256 tokenId) {
        // Given : Mint initial position
        (tokenId,,) = addLiquidityUniV3(
            pool,
            testVars.amountToken0,
            testVars.amountToken1,
            users.liquidityProvider,
            testVars.tickLower,
            testVars.tickUpper,
            true
        );

        // And : Generate fees for the position
        generateFees(testVars.feeAmount0, testVars.feeAmount1);
    }

    function generateFees(uint256 amount0ToGenerate, uint256 amount1ToGenerate) public {
        vm.startPrank(users.liquidityProvider);
        ISwapRouter02.ExactInputSingleParams memory exactInputParams;
        // Swap token0 for token1
        if (amount0ToGenerate > 0) {
            uint256 amount0ToSwap = ((amount0ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token0.decimals());

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            token0.approve(address(swapRouter), amount0ToSwap);

            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: usdStablePool.fee(),
                recipient: users.liquidityProvider,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
        }

        // Swap token1 for token0
        if (amount1ToGenerate > 0) {
            uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / usdStablePool.fee())) * 10 ** token1.decimals());

            deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
            token1.approve(address(swapRouter), amount1ToSwap);

            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: usdStablePool.fee(),
                recipient: users.liquidityProvider,
                amountIn: amount1ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
        }

        vm.stopPrank();
    }
}
