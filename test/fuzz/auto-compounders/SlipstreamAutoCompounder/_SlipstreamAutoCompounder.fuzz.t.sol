/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AerodromeFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/aerodrome/AerodromeFixture.f.sol";
import { Base_Test } from "../../../../lib/accounts-v2/test/Base.t.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ExactInputSingleParams } from "../../../../src/auto-compounders/slipstream/interfaces/ISwapRouter.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { ISwapRouter } from "../../../../src/auto-compounders/slipstream/interfaces/ISwapRouter.sol";
import { QuoterFixture } from "../../../utils/fixtures/slipstream/Quoter.f.sol";
import { SlipstreamAutoCompounder } from "../../../../src/auto-compounders/slipstream/SlipstreamAutoCompounder.sol";
import { SwapRouterFixture } from "../../../utils/fixtures/slipstream/SwapRouter.f.sol";
import { SlipstreamAMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { SlipstreamAutoCompounderExtension } from "../../../utils/extensions/SlipstreamAutoCompounderExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "SlipstreamAutoCompounder" fuzz tests.
 */
abstract contract SlipstreamAutoCompounder_Fuzz_Test is
    Fuzz_Test,
    AerodromeFixture,
    SlipstreamFixture,
    SwapRouterFixture,
    QuoterFixture
{
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

    ICLPoolExtension internal usdStablePool;

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

    SlipstreamAutoCompounderExtension internal autoCompounder;
    SlipstreamAMExtension internal slipstreamAM;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, SlipstreamFixture) {
        Fuzz_Test.setUp();

        AerodromeFixture.deployAerodromePeriphery();
        SlipstreamFixture.setUp();
        SlipstreamFixture.deploySlipstream();
        SwapRouterFixture.deploySwapRouter(address(cLFactory), address(weth9));
        QuoterFixture.deployQuoter(address(cLFactory), address(weth9));

        deploySlipstreamAM();
        deployAutoCompounder(COMPOUND_THRESHOLD, INITIATOR_SHARE, TOLERANCE);

        // Add two stable tokens with 6 and 18 decimals.
        token0 = new ERC20Mock("Token 6d", "TOK6", 6);
        token1 = new ERC20Mock("Token 18d", "TOK18", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        addAssetToArcadia(address(token0), int256(10 ** MOCK_ORACLE_DECIMALS));
        addAssetToArcadia(address(token1), int256(10 ** MOCK_ORACLE_DECIMALS));

        // Create UniswapV3 pool.
        uint256 sqrtPriceX96 = autoCompounder.getSqrtPriceX96(10 ** token1.decimals(), 10 ** token0.decimals());
        usdStablePool = createPoolCL(address(token0), address(token1), TICK_SPACING, uint160(sqrtPriceX96), 300);

        // And : AutoCompounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(autoCompounder), true);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAutoCompounder(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance) public {
        vm.prank(users.owner);
        autoCompounder = new SlipstreamAutoCompounderExtension(compoundThreshold, initiatorShare, tolerance);

        // Overwrite code hash of the CLPool.
        bytes memory bytecode = address(autoCompounder).code;

        // Overwrite contract addresses stored as constants in AutoCompounder.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x827922686190790b37229fd06084350E74485b72),
            abi.encodePacked(slipstreamPositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A), abi.encodePacked(cLFactory), false
        );
        vm.etch(address(autoCompounder), bytecode);
    }

    function givenValidBalancedState(TestVariables memory testVars)
        public
        view
        returns (TestVariables memory testVars_, bool token0HasLowestDecimals)
    {
        // Given : ticks should be in range
        (, int24 currentTick,,,,) = usdStablePool.slot0();

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

    function setState(TestVariables memory testVars, ICLPoolExtension pool) public returns (uint256 tokenId) {
        // Given : Mint initial position
        (tokenId,,) = addLiquidityCL(
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
        // Swap token0 for token1
        uint256 amount0ToSwap = ((amount0ToGenerate * (1e6 / POOL_FEE)) * 10 ** token0.decimals());

        deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

        vm.startPrank(users.liquidityProvider);
        token0.approve(address(swapRouter), amount0ToSwap);

        ExactInputSingleParams memory exactInputParams = ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            tickSpacing: TICK_SPACING,
            recipient: users.liquidityProvider,
            deadline: block.timestamp,
            amountIn: amount0ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        // Swap token1 for token0
        uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / POOL_FEE)) * 10 ** token1.decimals());

        deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
        token1.approve(address(swapRouter), amount1ToSwap);

        exactInputParams = ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            tickSpacing: TICK_SPACING,
            recipient: users.liquidityProvider,
            deadline: block.timestamp,
            amountIn: amount1ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        vm.stopPrank();
    }

    function deploySlipstreamAM() public {
        vm.startPrank(users.owner);
        // Add the Asset Module to the Registry.
        slipstreamAM = new SlipstreamAMExtension(address(registry), address(slipstreamPositionManager));

        registry.addAssetModule(address(slipstreamAM));
        slipstreamAM.setProtocol();
        vm.stopPrank();
    }
}
