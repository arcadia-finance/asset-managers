/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IQuoterV2 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IQuoterV2.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/LiquidityAmounts.sol";
import { PricingLogic } from "../../../../src/rebalancers/uniswap-v3/libraries/PricingLogic.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { SwapMath } from "../../../../src/rebalancers/libraries/SwapMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { Rebalancer } from "../../../../src/rebalancers/uniswap-v3/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "rebalancePosition" of contract "Rebalancer".
 */
contract RebalancePosition_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /* ///////////////////////////////////////////////////////////////
                              HELPERS
    /////////////////////////////////////////////////////////////// */

    function moveTicksRightWithIncreasedTolerance(address initiator, uint256 amount1ToSwap, bool maxRight) public {
        (uint160 sqrtPriceX96, int24 tickCurrent,,,,,) = uniV3Pool.slot0();
        uint128 liquidity_ = uniV3Pool.liquidity();

        (uint256 usdPriceToken0, uint256 usdPriceToken1) = getValuesInUsd();
        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);
        (uint256 upperSqrtPriceDeviation,,,) = rebalancer.initiatorInfo(initiator);
        // Calculate max sqrtPriceX96 to the right to avoid unbalancedPool()
        uint256 sqrtPriceX96Target = trustedSqrtPriceX96.mulDivDown(upperSqrtPriceDeviation, 1e18);

        // Take 5 % below to allow swapping and avoid unbalancedPool
        sqrtPriceX96Target -= ((sqrtPriceX96Target * (0.05 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the max amount of token 1 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity_, amountRemaining, 100 * POOL_FEE
        );

        // Amount to swap should be max equal to amountIn which will achieve the highest possible swap withing maxTolerance.
        if (maxRight) {
            amount1ToSwap = amountIn;
        } else {
            amount1ToSwap = bound(amount1ToSwap, 1, amountIn);
        }

        vm.startPrank(users.swapper);
        deal(address(token1), users.swapper, type(uint128).max);

        token1.approve(address(swapRouter), type(uint128).max);

        ISwapRouter02.ExactInputSingleParams memory exactInputParams;
        exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token1),
            tokenOut: address(token0),
            fee: uniV3Pool.fee(),
            recipient: users.swapper,
            amountIn: amount1ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);
        vm.stopPrank();

        (, int24 tick,,,,,) = uniV3Pool.slot0();
        vm.assume(tick > tickCurrent);
    }

    function moveTicksLeftWithIncreasedTolerance(int24 initLpLowerTick, uint256 amount0ToSwap, bool maxLeft) public {
        (uint160 sqrtPriceX96, int24 tickCurrent,,,,,) = uniV3Pool.slot0();
        uint128 liquidity_ = uniV3Pool.liquidity();

        // Calculate max sqrtPriceX96 to the left to avoid unbalancedPool()
        // No probleme in this case as lower ratio will be 0.
        // But we still want to be within initial lp range for liquidity
        uint256 sqrtPriceX96Target = TickMath.getSqrtRatioAtTick(initLpLowerTick);

        // Take 5 % above to ensure we are withing the liquidity and enable swapping without being unbalanced
        sqrtPriceX96Target += ((sqrtPriceX96Target * (0.05 * 1e18)) / 1e18);

        int256 amountRemaining = type(int128).max;
        // Calculate the max amount of token 0 to swap to achieve target price
        (, uint256 amountIn,,) = SwapMath.computeSwapStep(
            sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity_, amountRemaining, 100 * POOL_FEE
        );

        // Amount to swap should be max amountIn that will achieve the highest possible swap withing maxTolerance.
        if (maxLeft) {
            amount0ToSwap = amountIn;
        } else {
            amount0ToSwap = bound(amount0ToSwap, 1, amountIn);
        }

        vm.startPrank(users.swapper);
        deal(address(token0), users.swapper, type(uint128).max);

        token0.approve(address(swapRouter), type(uint128).max);

        ISwapRouter02.ExactInputSingleParams memory exactInputParams;
        exactInputParams = ISwapRouter02.ExactInputSingleParams({
            tokenIn: address(token0),
            tokenOut: address(token1),
            fee: uniV3Pool.fee(),
            recipient: users.swapper,
            amountIn: amount0ToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        swapRouter.exactInputSingle(exactInputParams);
        vm.stopPrank();

        (, int24 tick,,,,,) = uniV3Pool.slot0();
        vm.assume(tick < tickCurrent);
    }

    function getRebalanceParams(
        uint256 tokenId,
        int24 lpLowerTick,
        int24 lpUpperTick,
        Rebalancer.PositionState memory position,
        address initiator
    )
        public
        view
        returns (
            uint256 amount0,
            uint256 amount1,
            bool zeroToOne,
            uint256 amountIn,
            uint256 amountOut,
            uint256 amountInitiatorFee
        )
    {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(position.sqrtPriceX96),
            TickMath.getSqrtRatioAtTick(lpLowerTick),
            TickMath.getSqrtRatioAtTick(lpUpperTick),
            position.liquidity
        );

        {
            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);
            amount0 += fee0;
            amount1 += fee1;
        }

        (,, uint256 initiatorFee,) = rebalancer.initiatorInfo(initiator);

        (, zeroToOne, amountInitiatorFee, amountIn, amountOut) =
            rebalancer.getRebalanceParams(position, amount0, amount1, initiatorFee);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        address positionManager,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) public {
        vm.assume(account_ != address(0));
        // Given : account is not address(0)
        rebalancer.setAccount(account_);

        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.rebalancePosition(account_, positionManager, tokenId, tickLower, tickUpper, "");
    }

    function testFuzz_Revert_rebalancePosition_InitiatorNotValid(
        uint256 tokenId,
        address positionManager,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Given : Owner of the account has not set an initiator yet
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(Rebalancer.InitiatorNotValid.selector);
        rebalancer.rebalancePosition(address(account), positionManager, tokenId, tickLower, tickUpper, "");
    }

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, lpVars.tickLower - ((INIT_LP_TICK_RANGE / 2) - 100), lpVars.tickLower - 1));
        tickUpper = int24(bound(tickUpper, lpVars.tickUpper + 1, lpVars.tickUpper + ((INIT_LP_TICK_RANGE / 2) - 100)));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        vm.expectEmit();
        emit Rebalancer.Rebalance(address(account), address(nonfungiblePositionManager), tokenId);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, ""
        );

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual, uint256 liquidity,,,,) =
            nonfungiblePositionManager.positions(tokenId + 1);

        (, int24 tickCurrent,,,,,) = uniV3Pool.slot0();

        // There can be 1 tick difference due to roundings.
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual);

        (uint256 amount0_, uint256 amount1_) = LiquidityAmounts.getAmountsForLiquidity(
            TickMath.getSqrtRatioAtTick(tickCurrent),
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            uint128(liquidity)
        );
        (uint256 usdValuePosition, uint256 usdValueRemaining) =
            getValuesInUsd(amount0_, amount1_, token0.balanceOf(address(account)), token1.balanceOf(address(account)));
        // Ensure the leftovers represent less than 1,4% of the usd value of the newly minted position.
        assertLt(usdValueRemaining, 0.014 * 1e18 * usdValuePosition / 1e18);
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token0(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickUpper
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : Move upper tick to the right (should trigger a oneToZero swap)
        int24 tickLower = lpVars.tickLower;
        tickUpper = int24(bound(tickUpper, lpVars.tickUpper + 10, lpVars.tickUpper + ((INIT_LP_TICK_RANGE / 2) - 100)));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        uint256 expectedFee;
        {
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
            vm.assume(zeroToOne == false);
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, ""
        );

        // Then : It should return the correct values
        assertGt(token1.balanceOf(initVars.initiator), 0);
        assertLe(token1.balanceOf(initVars.initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_InitiatorFees_Token1(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : Move lower tick to the left (should trigger a zeroToOne swap)
        tickLower = int24(bound(tickLower, lpVars.tickLower - ((INIT_LP_TICK_RANGE / 2) - 100), lpVars.tickLower - 10));
        int24 tickUpper = lpVars.tickUpper;

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        uint256 expectedFee;
        {
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
            );
            bool zeroToOne;
            uint256 amountIn;
            (,, zeroToOne, amountIn,, expectedFee) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initVars.initiator);
            vm.assume(zeroToOne == true);
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, ""
        );

        // Then : It should return the correct values
        assertGt(token0.balanceOf(initVars.initiator), 0);
        assertLe(token0.balanceOf(initVars.initiator), expectedFee);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount1ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // Move ticks right (by maxTolerance in this case 1e18 = 100%)
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, false);

        (, int24 tickBeforeRebalance,,,,,) = uniV3Pool.slot0();

        // When : calling rebalancePosition() with 0 value for lower and upper ticks
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(address(account), address(nonfungiblePositionManager), tokenId, 0, 0, "");

        // Then : It should return correct values
        int24 halfRangeTicks;
        {
            int24 tickSpacing = uniV3Pool.tickSpacing();
            halfRangeTicks = (((lpVars.tickUpper - lpVars.tickLower)) / tickSpacing) / 2;
            halfRangeTicks *= tickSpacing;
        }
        int24 tickUpperExpected = tickBeforeRebalance + halfRangeTicks;
        int24 tickLowerExpected = tickBeforeRebalance - halfRangeTicks;
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickUpperExpected, tickUpper);
        assertEq(tickLowerExpected, tickLower);
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount0ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // Move ticks left
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, false);

        (, int24 tickBeforeRebalance,,,,,) = uniV3Pool.slot0();

        // When : calling rebalancePosition() with 0 value for lower and upper ticks
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(address(account), address(nonfungiblePositionManager), tokenId, 0, 0, "");

        // Then : It should return correct values
        int24 halfRangeTicks;
        {
            int24 tickSpacing = uniV3Pool.tickSpacing();
            halfRangeTicks = (((lpVars.tickUpper - lpVars.tickLower)) / tickSpacing) / 2;
            halfRangeTicks *= tickSpacing;
        }
        int24 tickUpperExpected = tickBeforeRebalance + halfRangeTicks;
        int24 tickLowerExpected = tickBeforeRebalance - halfRangeTicks;
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickUpperExpected, tickUpper);
        assertEq(tickLowerExpected, tickLower);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_CustomTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount1ToSwap
    ) public {
        initVars = InitVariables({
            tickLower: -6,
            tickUpper: 25,
            initToken0Amount: 1_254_146_707_194_178_096_176_766_673_175_240_249,
            initToken1Amount: 736_207_616_195_098_419_872_245_438,
            token0Decimals: 61,
            token1Decimals: 12,
            priceToken0: 50,
            priceToken1: 11_709_559_248_905_314_546_114_447_808_662_921_227,
            decimalsDiff: 124_717_623_019_461_639_191_522_877_589_059_513,
            initiator: 0xd580A42e94D62A35D75fbe8955925652C7e0E2E7,
            tolerance: 2_090_838_823_228_657_192_212_738_185,
            fee: 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_935
        });
        lpVars = LpVariables({
            tickLower: -2,
            tickUpper: 8_388_606,
            liquidity: 16_092_574_269_830_985_068_916_356_142_974_106_755,
            amount0: 1_597_969_176_353_669_679_796_448_253_419_886_846_293_756_449_577_404_681_680_139_099_113_796_557,
            amount1: 184_805_926_269
        });
        tickLower = 150_841;
        tickUpper = -5;
        amount1ToSwap = 1_080_237_021_945_869_010_359_923_759_788_300;
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // Ticks have moved to the right
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, false);

        {
            address initiatorStack = initVars.initiator;
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initiatorStack
            );
            (uint256 amount0, uint256 amount1, bool zeroToOne, uint256 amountIn,,) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initiatorStack);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            (uint256 amountOut, uint160 sqrtPriceAfter,,) = quoter.quoteExactInputSingle(params);

            if (zeroToOne) {
                amount0 -= amountIn;
                amount1 += amountOut;
            } else {
                amount0 += amountOut;
                amount1 -= amountIn;
            }

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceAfter,
                TickMath.getSqrtRatioAtTick(position_.tickLower),
                TickMath.getSqrtRatioAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            vm.assume(liquidity > 0);
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, ""
        );

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual);
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_CustomTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // Ticks have moved to the right
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, false);

        uint256 amount0;
        uint256 amount1;
        {
            // Avoid stack too deep
            address initiatorStack = initVars.initiator;
            // Assume that liquidity will be bigger than 0
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initiatorStack
            );

            uint256 amountIn;
            bool zeroToOne;
            (amount0, amount1, zeroToOne, amountIn,,) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initiatorStack);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            (uint256 amountOut, uint160 sqrtPriceAfter,,) = quoter.quoteExactInputSingle(params);

            if (zeroToOne) {
                amount0 -= amountIn;
                amount1 += amountOut;
            } else {
                amount0 += amountOut;
                amount1 -= amountIn;
            }

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceAfter,
                TickMath.getSqrtRatioAtTick(position_.tickLower),
                TickMath.getSqrtRatioAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            vm.assume(liquidity > 0);
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, ""
        );

        // Then : It should return the correct values
        (,,,,, int24 tickLowerActual, int24 tickUpperActual,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, tickLowerActual);
        assertEq(tickUpper, tickUpperActual);
    }

    function testFuzz_Success_rebalancePosition_ArbitrarySwap_ZeroToOne(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        uint256 amount1ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // And : Move ticks to max right to ensure zeroToOne swap
        moveTicksRightWithIncreasedTolerance(initVars.initiator, amount1ToSwap, true);

        // Avoid stack too deep
        address initiatorStack = initVars.initiator;
        LpVariables memory lpVarsStack = lpVars;

        uint256 amountIn;
        uint256 amountOut;
        {
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager),
                tokenId,
                lpVarsStack.tickLower,
                lpVarsStack.tickUpper,
                initiatorStack
            );

            uint256 amount0;
            uint256 amount1;
            bool zeroToOne;
            (amount0, amount1, zeroToOne, amountIn, amountOut,) =
                getRebalanceParams(tokenId, lpVarsStack.tickLower, lpVarsStack.tickUpper, position_, initiatorStack);

            // And : Should be a zeroToOneSwap
            vm.assume(zeroToOne == true);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            uint160 sqrtPriceAfter;
            (amountOut, sqrtPriceAfter,,) = quoter.quoteExactInputSingle(params);

            amount0 -= amountIn;
            amount1 += amountOut;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceAfter,
                TickMath.getSqrtRatioAtTick(position_.tickLower),
                TickMath.getSqrtRatioAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            // And : Liquidity should be > 0
            vm.assume(liquidity > 0);
        }

        bytes memory swapData;
        {
            // Send token1 (amountOut) to router for swap
            deal(address(token1), address(routerMock), type(uint128).max);

            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), amountIn, amountOut);
            swapData = abi.encode(address(routerMock), amountIn, routerData);
        }

        // When : Calling rebalancePosition()
        // Then : It should process an Arbitrary swap.
        vm.prank(initVars.initiator);
        vm.expectEmit();
        emit RouterMock.ArbitrarySwap(true);
        rebalancer.rebalancePosition(
            address(account),
            address(nonfungiblePositionManager),
            tokenId,
            lpVarsStack.tickLower,
            lpVarsStack.tickUpper,
            swapData
        );
    }

    function testFuzz_Success_rebalancePosition_ArbitrarySwap_OneToZero(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToSwap
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(maxTolerance, MAX_INITIATOR_FEE);

        // And : Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And : Allow to test with increased tolerance
        increaseTolerance = true;

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        tickLower = int24(bound(tickLower, initVars.tickLower + 1, initVars.tickUpper - (2 * MIN_TICK_SPACING)));
        tickUpper = int24(bound(tickUpper, tickLower + MIN_TICK_SPACING, initVars.tickUpper - 1));

        // And : Set initiator for account
        vm.prank(account.owner());
        rebalancer.setInitiatorForAccount(initVars.initiator, address(account));

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

        // And : Move ticks left to enable oneToZero swap
        moveTicksLeftWithIncreasedTolerance(initVars.tickLower, amount0ToSwap, true);

        uint256 amount0;
        uint256 amount1;
        uint256 amountIn;
        uint256 amountOut;
        {
            // Avoid stack too deep
            address initiatorStack = initVars.initiator;
            // Assume that liquidity will be bigger than 0
            Rebalancer.PositionState memory position_ = rebalancer.getPositionState(
                address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initiatorStack
            );

            bool zeroToOne;
            (amount0, amount1, zeroToOne, amountIn, amountOut,) =
                getRebalanceParams(tokenId, lpVars.tickLower, lpVars.tickUpper, position_, initiatorStack);

            // And : We want to test for a oneToZero swap
            vm.assume(zeroToOne == false);

            IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: zeroToOne ? address(token0) : address(token1),
                tokenOut: zeroToOne ? address(token1) : address(token0),
                amountIn: amountIn,
                fee: position_.fee,
                sqrtPriceLimitX96: 0
            });

            uint160 sqrtPriceAfter;
            (amountOut, sqrtPriceAfter,,) = quoter.quoteExactInputSingle(params);

            amount0 += amountOut;
            amount1 -= amountIn;

            uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
                sqrtPriceAfter,
                TickMath.getSqrtRatioAtTick(position_.tickLower),
                TickMath.getSqrtRatioAtTick(position_.tickUpper),
                amount0,
                amount1
            );

            // And : Liquidity minted should be bigger than zero
            vm.assume(liquidity > 0);
        }

        bytes memory swapData;
        {
            // Send token0 (amountOut) to router for swap
            deal(address(token0), address(routerMock), type(uint128).max);

            bytes memory routerData =
                abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), amountIn, amountOut);
            swapData = abi.encode(address(routerMock), amountIn, routerData);
        }

        // When : calling rebalancePosition()
        // Then : It should process to an arbitrary swap
        vm.prank(initVars.initiator);
        vm.expectEmit();
        emit RouterMock.ArbitrarySwap(true);
        rebalancer.rebalancePosition(
            address(account), address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, swapData
        );
    }
}
