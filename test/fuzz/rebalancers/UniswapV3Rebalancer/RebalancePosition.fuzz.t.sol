/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../../../../src/libraries/ArcadiaLogic.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { LiquidityAmounts } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/LiquidityAmounts.sol";
import { QuoteExactOutputSingleParams } from "../../../../src/interfaces/uniswap-v3/IQuoter.sol";
import { SwapMath } from "../../../../src/libraries/SwapMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

/**
 * @notice Fuzz tests for the function "rebalancePosition" of contract "UniswapV3Rebalancer".
 */
contract RebalancePosition_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // We keep track of the tickChange variable here to avoid stack too deep issues.
    int24 tickChange;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    // TODO : delete
    event Logg(uint256);

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(0));
        // Given : account is not address(0)
        rebalancer.setAccount(account_);

        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.Reentered.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_NotAnAccount(
        address account_,
        uint256 tokenId,
        int24 lowerTick,
        int24 upperTick
    ) public {
        vm.assume(account_ != address(account));
        // Given : account is not an Arcadia Account
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.NotAnAccount.selector);
        rebalancer.rebalancePosition(account_, tokenId, lowerTick, upperTick);
    }

    function testFuzz_Revert_rebalancePosition_InitiatorNotValid(uint256 tokenId, int24 lowerTick, int24 upperTick)
        public
    {
        // Given : Owner of the account has not set an initiator yet
        // When : calling rebalancePosition
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.InitiatorNotValid.selector);
        rebalancer.rebalancePosition(address(account), tokenId, lowerTick, upperTick);
    }

    function testFuzz_Success_rebalancePosition_SamePriceNewTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // Given : new ticks are within boundaries (otherwise swap too big => unbalanced pool)
        newLowerTick = int24(bound(newLowerTick, lpVars.tickLower - 200, lpVars.tickLower - 1));
        newUpperTick = int24(bound(newUpperTick, lpVars.tickUpper + 1, lpVars.tickUpper + 200));

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

        {
            // Calculate the amountOut in order to obtain tickChange after swap.
            UniswapV3Rebalancer.PositionState memory position =
                rebalancer.getPositionState(tokenId, newLowerTick, newUpperTick, initVars.initiator);

            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            uint256 amount0 = lpVars.amount0 + fee0;
            uint256 amount1 = lpVars.amount1 + fee1;

            uint256 sqrtRatioUpperTick = TickMath.getSqrtRatioAtTick(position.newUpperTick);
            uint256 sqrtRatioLowerTick = TickMath.getSqrtRatioAtTick(position.newLowerTick);
            // Get target ratio in token1 terms.
            uint256 targetRatio =
                UniswapV3Logic._getTargetRatio(position.sqrtPriceX96, sqrtRatioLowerTick, sqrtRatioUpperTick);

            // Calculate the total fee value in token1 equivalent:
            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            UniswapV3Rebalancer.PositionState memory positionStack = position;

            bool zeroToOne;
            uint256 amountOut;
            if (currentRatio < targetRatio) {
                // Swap token0 partially to token1.
                zeroToOne = true;
                amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, 1e18);
            } else {
                // Swap token1 partially to token0.
                zeroToOne = false;
                uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, 1e18);
                amountOut = UniswapV3Logic._getAmountOut(positionStack.sqrtPriceX96, false, amountIn);
            }

            QuoteExactOutputSingleParams memory params = QuoteExactOutputSingleParams({
                tokenIn: zeroToOne ? positionStack.token0 : positionStack.token1,
                tokenOut: zeroToOne ? positionStack.token1 : positionStack.token0,
                amountOut: amountOut,
                fee: positionStack.fee,
                sqrtPriceLimitX96: 0
            });
            (, uint160 sqrtPriceX96After,,) = quoter.quoteExactOutputSingle(params);
            int24 currentTick = TickMath.getTickAtSqrtRatio(uint160(positionStack.sqrtPriceX96));
            int24 tickAfter = TickMath.getTickAtSqrtRatio(sqrtPriceX96After);
            tickChange = tickAfter - currentTick;
        }

        // When : calling rebalancePosition()
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(address(account), tokenId, newLowerTick, newUpperTick);

        // Then : It should return the correct values
        (,,,,, int24 tickLower, int24 tickUpper, uint256 liquidity,,,,) =
            nonfungiblePositionManager.positions(tokenId + 1);
        assertEq(tickLower, newLowerTick + tickChange);
        assertEq(tickUpper, newUpperTick + tickChange);

        uint256 amount0_ = LiquidityAmounts.getAmount0ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(liquidity)
        );
        uint256 amount1_ = LiquidityAmounts.getAmount1ForLiquidity(
            TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), uint128(liquidity)
        );
        (uint256 usdValuePosition, uint256 usdValueRemaining) =
            getValuesInUsd(amount0_, amount1_, token0.balanceOf(address(account)), token1.balanceOf(address(account)));

        // Ensure the leftovers represent less than 0,5% of the usd value of the newly minted position.
        assertLt(usdValueRemaining, 0.005 * 1e18 * usdValuePosition / 1e18);
    }

    function testFuzz_Success_rebalancePosition_MoveTickRight_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars
    ) public {
        // Given : deploy new rebalancer with a high maxTolerance to avoid unbalancedPool due to external usd prices not aligned
        uint256 maxTolerance = 1e18;
        deployRebalancer(LIQUIDITY_TRESHOLD, maxTolerance);

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
        {
            (uint160 sqrtPriceX96, int24 currentTick,,,,,) = uniV3Pool.slot0();
            uint128 liquidity_ = uniV3Pool.liquidity();

            (uint256 usdPriceToken0, uint256 usdPriceToken1) = getValuesInUsd();
            // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD price of both tokens.
            uint256 trustedSqrtPriceX96 = UniswapV3Logic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);
            (uint256 upperSqrtPriceDeviation,,) = rebalancer.initiatorInfo(initVars.initiator);
            // Calculate max sqrtPriceX96 to the right to avoid unbalancedPool()
            uint256 sqrtPriceX96Target = trustedSqrtPriceX96.mulDivDown(upperSqrtPriceDeviation, 1e18);

            // Take 1 % below to ensure we avoid unbalancedPool
            sqrtPriceX96Target -= ((sqrtPriceX96Target * (0.01 * 1e18)) / 1e18);

            int256 amountRemaining = type(int128).max;
            // Calculate the minimum amount of token 1 to swap to achieve target price
            (, uint256 amountIn,,) = SwapMath.computeSwapStep(
                sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity_, amountRemaining, 100 * POOL_FEE
            );

            vm.startPrank(users.swapper);
            deal(address(token1), users.swapper, type(uint128).max);

            token1.approve(address(swapRouter), type(uint128).max);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams;
            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: uniV3Pool.fee(),
                recipient: users.swapper,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
            vm.stopPrank();

            (, int24 tick,,,,,) = uniV3Pool.slot0();
            vm.assume(tick > currentTick);
        }

        // When : calling rebalancePosition() with 0 value for lower and upper ticks
        vm.prank(initVars.initiator);
        rebalancer.rebalancePosition(address(account), tokenId, 0, 0);

        // Then : It should return correct values
        int24 tickSpacing = (lpVars.tickUpper - lpVars.tickLower) / 2;
        (, int24 newTick,,,,,) = uniV3Pool.slot0();
        (,,,,, int24 tickLower, int24 tickUpper,,,,,) = nonfungiblePositionManager.positions(tokenId + 1);

        assertEq(tickLower, newTick - tickSpacing);
        assertEq(tickUpper, newTick + tickSpacing);
    }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_BalancedWithSameTickSpacing(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public { }

    function testFuzz_Success_rebalancePosition_MoveTickRight_CustomTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public { }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_CustomTicks(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public { }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_CustomTicks_SingleSided0(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public { }

    function testFuzz_Success_rebalancePosition_MoveTickLeft_CustomTicks_SingleSided1(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newLowerTick,
        int24 newUpperTick
    ) public { }
}
