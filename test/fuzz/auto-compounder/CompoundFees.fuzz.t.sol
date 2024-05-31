/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AutoCompounder_Fuzz_Test } from "./_AutoCompounder.fuzz.t.sol";

import { AutoCompounder } from "../../../src/auto-compounder/AutoCompounder.sol";
import { ERC20Mock } from "../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { ISwapRouter02 } from "../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { IUniswapV3PoolExtension } from
    "../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";

/**
 * @notice Fuzz tests for the function "compoundFees" of contract "AutoCompounder".
 */
contract CompoundFees_AutoCompounder_Fuzz_Test is AutoCompounder_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    int24 internal MAX_TICK_VALUE = 887_272;
    uint256 internal MOCK_ORACLE_DECIMALS = 18;
    uint24 internal POOL_FEE = 100;

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

    IUniswapV3PoolExtension internal usdStablePool;

    struct TestVariables {
        int24 tickLower;
        int24 tickUpper;
        uint112 amountToken0;
        uint112 amountToken1;
        // Fee amounts in usd
        uint256 feeAmount0;
        uint256 feeAmount1;
    }

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        AutoCompounder_Fuzz_Test.setUp();

        deployArcadiaAccounts();
        deployUniswapV3();
        deploySwapRouter02();
        deployQuoterV2();

        deployUniswapV3AM();
        deployAutoCompounder(COMPOUND_THRESHOLD, INITIATOR_SHARE, TOLERANCE);

        // Add two stable tokens with 6 and 18 decimals.
        token0 = new ERC20Mock("Token 6d", "TOK6", 6);
        token1 = new ERC20Mock("Token 18d", "TOK18", 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);

        AddAsset(token0, int256(10 ** MOCK_ORACLE_DECIMALS));
        AddAsset(token1, int256(10 ** MOCK_ORACLE_DECIMALS));

        // Create UniswapV3 pool.
        uint256 sqrtPriceX96 = autoCompounder.getSqrtPriceX96(10 ** token1.decimals(), 10 ** token0.decimals());
        usdStablePool = createPool(address(token0), address(token1), POOL_FEE, uint160(sqrtPriceX96), 300);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compoundFees_FeeAmountTooLow(TestVariables memory testVars, address initiator) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars);

        // And : Fee amounts are too low
        testVars.feeAmount0 = ((COMPOUND_THRESHOLD / 2e18) - 1);
        testVars.feeAmount1 = ((COMPOUND_THRESHOLD / 2e18) - 1);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : AutoCompounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(autoCompounder), true);

        // When : Calling compoundFees()
        vm.startPrank(initiator);
        vm.expectRevert(AutoCompounder.BelowThreshold.selector);
        autoCompounder.compoundFees(address(account), tokenId);
        vm.stopPrank();
    }

    function testFuzz_Success_compoundFees(TestVariables memory testVars, address initiator) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : AutoCompounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(autoCompounder), true);

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // When : Calling compoundFees()
        vm.prank(initiator);
        autoCompounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = testVars.feeAmount0 * 10 ** token0.decimals();
        uint256 totalFee1 = testVars.feeAmount1 * 10 ** token1.decimals();

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        initiatorFeeToken0Calculated = initiatorFeeToken0Calculated;
        initiatorFeeToken1Calculated = initiatorFeeToken1Calculated;
        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }

    function testFuzz_Success_compoundFees_MoveTickRight(TestVariables memory testVars, address initiator) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : AutoCompounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(autoCompounder), true);

        // And : Move tick right
        uint256 amount1ToSwap;
        {
            // Swap max amount to move ticks left (ensure tolerance is not exceeded when compounding afterwards)
            amount1ToSwap = 100_000_000_000_000 * 10 ** token1.decimals();

            deal(address(token1), users.liquidityProvider, amount1ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token1.approve(address(swapRouter), amount1ToSwap);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: POOL_FEE,
                recipient: users.liquidityProvider,
                amountIn: amount1ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);

            vm.stopPrank();
        }

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // When : Calling compoundFees()
        vm.prank(initiator);
        autoCompounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : Initiator fees should have been distributed
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = testVars.feeAmount0 * 10 ** token0.decimals();
        uint256 totalFee1 = testVars.feeAmount1 * 10 ** token1.decimals();

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);

        if (token0.decimals() < token1.decimals()) {
            uint256 dustToken0InUsdValue = (initiatorFeesToken0 + 1) - initiatorFeeToken0Calculated * 1e30 / 1e18;
            uint256 dustToken1InUsdValue = (initiatorFeesToken1 + 1) - initiatorFeeToken1Calculated * 1e18 / 1e18;

            uint256 totalFee0InUsd = totalFee0 * 1e30 / 1e18;
            uint256 totalFee1InUsd = totalFee1 * 1e18 / 1e18;

            // Ensure dust represents max 3% from fees (is dependent on tolerance and tick range)
            // We keep relatively high tolerance as otherwise we are not able to move the tick enough
            // Dust amount decreases when lower tolerance
            assertLe(dustToken0InUsdValue + dustToken1InUsdValue, (totalFee0InUsd + totalFee1InUsd) * 300 / 1e18);
        } else {
            uint256 dustToken0InUsdValue = ((initiatorFeesToken0 + 1) - initiatorFeeToken0Calculated) * 1e18 / 1e18;
            uint256 dustToken1InUsdValue = ((initiatorFeesToken1 + 1) - initiatorFeeToken1Calculated) * 1e30 / 1e18;

            uint256 totalFee0InUsd = totalFee0 * 1e18 / 1e18;
            uint256 totalFee1InUsd = totalFee1 * 1e30 / 1e18;

            // Ensure dust represents max 3% from fees (is dependent on tolerance and tick range)
            // We keep relatively high tolerance as otherwise we are not able to move the tick enough
            // Dust amount decreases when lower tolerance
            assertLe(dustToken0InUsdValue + dustToken1InUsdValue, 300 * (totalFee0InUsd + totalFee1InUsd) / 1e18);
        }
    }

    function testFuzz_Success_compoundFees_MoveTickLeft(TestVariables memory testVars, address initiator) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : AutoCompounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(autoCompounder), true);

        // And : Move tick right
        uint256 amount0ToSwap;
        {
            // Swap max amount to move ticks right (ensure tolerance is not exceeded when compounding afterwards)
            amount0ToSwap = 100_000_000_000_000 * 10 ** token0.decimals();

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token0.approve(address(swapRouter), amount0ToSwap);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: POOL_FEE,
                recipient: users.liquidityProvider,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);

            vm.stopPrank();
        }

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // When : Calling compoundFees()
        vm.prank(initiator);
        autoCompounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : Initiator fees should have been distributed
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = (testVars.feeAmount0 * 10 ** token0.decimals()) + (amount0ToSwap * 1 / 1e18);
        uint256 totalFee1 = (testVars.feeAmount1 * 10 ** token1.decimals());

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);

        if (token0.decimals() < token1.decimals()) {
            uint256 dustToken0InUsdValue = (initiatorFeesToken0 - initiatorFeeToken0Calculated) * 1e30 / 1e18;
            uint256 dustToken1InUsdValue = (initiatorFeesToken1 + 1 - initiatorFeeToken1Calculated) * 1e18 / 1e18;

            uint256 totalFee0InUsd = totalFee0 * 1e30 / 1e18;
            uint256 totalFee1InUsd = totalFee1 * 1e18 / 1e18;

            // Ensure dust represents max 3% from fees (is dependent on tolerance and tick range)
            // We keep relatively high tolerance as otherwise we are not able to move the tick enough
            // Dust amount decreases when lower tolerance
            assertLe(dustToken0InUsdValue + dustToken1InUsdValue, 300 * (totalFee0InUsd + totalFee1InUsd) / 1e18);
        } else {
            uint256 dustToken0InUsdValue = (initiatorFeesToken0 - initiatorFeeToken0Calculated) * 1e18 / 1e18;
            uint256 dustToken1InUsdValue = (initiatorFeesToken1 + 1 - initiatorFeeToken1Calculated) * 1e30 / 1e18;

            uint256 totalFee0InUsd = totalFee0 * 1e18 / 1e18;
            uint256 totalFee1InUsd = totalFee1 * 1e30 / 1e18;

            // Ensure dust represents max 2% from fees (is dependent on tolerance and tick range)
            // We keep relatively high tolerance as otherwise we are not able to move the tick enough
            // Dust amount decreases when lower tolerance
            assertLe(dustToken0InUsdValue + dustToken1InUsdValue, 300 * (totalFee0InUsd + totalFee1InUsd) / 1e18);
        }
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

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
        (tokenId,,) = addLiquidity(
            pool,
            testVars.amountToken0,
            testVars.amountToken1,
            users.liquidityProvider,
            testVars.tickLower,
            testVars.tickUpper
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

        ISwapRouter02.ExactInputSingleParams memory exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: POOL_FEE,
            recipient: users.liquidityProvider,
            amountIn: amount0ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        // Swap token1 for token0
        uint256 amount1ToSwap = ((amount1ToGenerate * (1e6 / POOL_FEE)) * 10 ** token1.decimals());

        deal(address(token1), users.liquidityProvider, amount1ToSwap, true);
        token1.approve(address(swapRouter), amount1ToSwap);

        exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: POOL_FEE,
            recipient: users.liquidityProvider,
            amountIn: amount1ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);

        vm.stopPrank();
    }
}
