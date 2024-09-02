/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getSwapParameters" of contract "UniswapV3Rebalancer".
 */
contract GetSwapParameters_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_getSwapParameters_singleSidedToken0(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newUpperTick,
        int24 newLowerTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = uniV3Pool.slot0();

        // And : Ticks should be > current tick
        newLowerTick = int24(bound(newLowerTick, currentTick + 1, initVars.tickUpper));
        newUpperTick =
            int24(bound(newUpperTick, newLowerTick + MIN_TICK_SPACING, initVars.tickUpper + MIN_TICK_SPACING));

        (,,,,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        UniswapV3Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.liquidity = liquidity;
        position.newUpperTick = newUpperTick;
        position.newLowerTick = newLowerTick;

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        // And : Get token balances of position + fees.
        uint256 amount1;
        uint256 amount0;
        {
            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(position.sqrtPriceX96),
                TickMath.getSqrtRatioAtTick(lpVars.tickLower),
                TickMath.getSqrtRatioAtTick(lpVars.tickUpper),
                position.liquidity
            );
            amount0 += fee0;
            amount1 += fee1;
        }

        // When : calling getSwapParameters
        (,, uint256 initiatorFee) = rebalancer.initiatorInfo(initVars.initiator);
        (bool zeroToOne, uint256 amountIn) = rebalancer.getSwapParameters(position, amount0, amount1, initiatorFee);

        // Then : It should return correct values
        assertEq(zeroToOne, false);
        assertEq(amountIn, amount1);
    }

    function testFuzz_Success_getSwapParameters_singleSidedToken1(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newUpperTick,
        int24 newLowerTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = uniV3Pool.slot0();

        // And : Ticks should be < current tick
        newUpperTick = int24(bound(newUpperTick, initVars.tickLower, currentTick - 1));
        newLowerTick =
            int24(bound(newLowerTick, initVars.tickLower - MIN_TICK_SPACING, newUpperTick - MIN_TICK_SPACING));

        (,,,,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        UniswapV3Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.liquidity = liquidity;
        position.newUpperTick = newUpperTick;
        position.newLowerTick = newLowerTick;

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        // And : Get token balances of position + fees.
        uint256 amount0;
        uint256 amount1;
        {
            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            (amount0,) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(position.sqrtPriceX96),
                TickMath.getSqrtRatioAtTick(lpVars.tickLower),
                TickMath.getSqrtRatioAtTick(lpVars.tickUpper),
                position.liquidity
            );
            amount0 += fee0;
            amount1 += fee1;
        }

        // When : calling getSwapParameters
        (,, uint256 initiatorFee) = rebalancer.initiatorInfo(initVars.initiator);
        (bool zeroToOne, uint256 amountIn) = rebalancer.getSwapParameters(position, amount0, amount1, initiatorFee);

        // Then : It should return correct values
        assertEq(zeroToOne, true);
        // We test in rebalancePosition() that new position is fully in token1
        assertEq(amountIn, amount0);
    }

    function testFuzz_Success_getSwapParameters_currentRatioLowerThanTarget(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newUpperTick,
        int24 newLowerTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = uniV3Pool.slot0();

        // And : Tick range should include current tick
        newUpperTick = int24(bound(newUpperTick, currentTick + MIN_TICK_SPACING, initVars.tickUpper - 1));
        newLowerTick = int24(bound(newLowerTick, initVars.tickLower + 1, currentTick - MIN_TICK_SPACING));

        (,,,,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        UniswapV3Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.liquidity = liquidity;
        position.newUpperTick = newUpperTick;
        position.newLowerTick = newLowerTick;
        position.fee = uniV3Pool.fee();

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        (,, uint256 initiatorFee) = rebalancer.initiatorInfo(initVars.initiator);

        // Avoid stack too deep
        LpVariables memory lpVars_ = lpVars;
        uint24 fee = position.fee;

        // And : Calculate expected amount in
        uint256 expectedAmountIn;
        uint256 amount0;
        uint256 amount1;
        {
            uint256 targetRatio = UniswapV3Logic._getTargetRatio(
                position.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.newLowerTick),
                TickMath.getSqrtRatioAtTick(position.newUpperTick)
            );

            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(position.sqrtPriceX96),
                TickMath.getSqrtRatioAtTick(lpVars_.tickLower),
                TickMath.getSqrtRatioAtTick(lpVars_.tickUpper),
                position.liquidity
            );
            amount0 += fee0;
            amount1 += fee1;

            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            vm.assume(currentRatio < targetRatio);

            uint256 denominator = 1e18 + targetRatio.mulDivDown(fee, 1e6 - fee);
            uint256 amountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, denominator);
            // convert to amountIn
            expectedAmountIn = UniswapV3Logic._getAmountIn(position.sqrtPriceX96, true, amountOut, fee);
        }

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountIn) = rebalancer.getSwapParameters(position, amount0, amount1, initiatorFee);

        // Then : It should return correct values
        assertEq(zeroToOne, true);
        assertEq(amountIn, expectedAmountIn);
    }

    function testFuzz_Success_getSwapParameters_targetRatioLowerThanCurrent(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 newUpperTick,
        int24 newLowerTick
    ) public {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        (uint160 sqrtPriceX96, int24 currentTick,,,,,) = uniV3Pool.slot0();

        // And : Tick range should include current tick
        newUpperTick = int24(bound(newUpperTick, currentTick + MIN_TICK_SPACING, initVars.tickUpper - 1));
        newLowerTick = int24(bound(newLowerTick, initVars.tickLower + 1, currentTick - MIN_TICK_SPACING));

        (,,,,,,, uint128 liquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        UniswapV3Rebalancer.PositionState memory position;
        position.sqrtPriceX96 = sqrtPriceX96;
        position.liquidity = liquidity;
        position.newUpperTick = newUpperTick;
        position.newLowerTick = newLowerTick;
        position.fee = uniV3Pool.fee();

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        (,, uint256 initiatorFee) = rebalancer.initiatorInfo(initVars.initiator);

        // Avoid stack too deep
        int24 tickLowerStack = lpVars.tickLower;
        int24 tickUpperStack = lpVars.tickUpper;

        uint256 expectedAmountIn;
        uint256 amount0;
        uint256 amount1;
        {
            uint256 targetRatio = UniswapV3Logic._getTargetRatio(
                position.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.newLowerTick),
                TickMath.getSqrtRatioAtTick(position.newUpperTick)
            );

            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                uint160(position.sqrtPriceX96),
                TickMath.getSqrtRatioAtTick(tickLowerStack),
                TickMath.getSqrtRatioAtTick(tickUpperStack),
                position.liquidity
            );

            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            amount0 += fee0;
            amount1 += fee1;

            // Calculate the total fee value in token1 equivalent:
            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            vm.assume(targetRatio < currentRatio);

            uint256 denominator = 1e18 - targetRatio.mulDivDown(uniV3Pool.fee(), 1e6);
            expectedAmountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, denominator);
        }

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountIn) = rebalancer.getSwapParameters(position, amount0, amount1, initiatorFee);

        // Then : It should return correct values
        assertEq(zeroToOne, false);
        assertEq(amountIn, expectedAmountIn);
    }
}
