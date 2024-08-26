/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";
import { UniswapV3Logic } from "../../../../src/libraries/UniswapV3Logic.sol";

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

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountOut, int24 tickChange) = rebalancer.getSwapParameters(position, tokenId);

        // Then : It should return correct values
        assertEq(zeroToOne, false);
        // We test in rebalancePosition() that new position is fully in token0
        assertGt(amountOut, 0);
        // TODO : tickChange
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

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountOut, int24 tickChange) = rebalancer.getSwapParameters(position, tokenId);

        // Then : It should return correct values
        assertEq(zeroToOne, true);
        // We test in rebalancePosition() that new position is fully in token1
        assertGt(amountOut, 0);
        // TODO : tickChange
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

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        uint256 expectedAmountOut;
        {
            uint256 targetRatio = UniswapV3Logic._getTargetRatio(
                position.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.newLowerTick),
                TickMath.getSqrtRatioAtTick(position.newUpperTick)
            );

            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            uint256 amount0 = lpVars.amount0 + fee0;
            uint256 amount1 = lpVars.amount1 + fee1;

            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            vm.assume(currentRatio < targetRatio);

            expectedAmountOut = (targetRatio - currentRatio).mulDivDown(totalValueInToken1, 1e18);
        }

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountOut, int24 tickChange) = rebalancer.getSwapParameters(position, tokenId);

        // Then : It should return correct values
        assertEq(zeroToOne, true);
        // Here we use approxEqRel as the difference between getAmountsForLiquidity() and the effective mint of a new position
        // might slightly differ (we check to max 1% diff)
        // TODO: validate why diff (first do full testing ?)
        //assertApproxEqRel(amountOut, expectedAmountOut, 1e16);
        // TODO : tickChange
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

        // And : Approve nft manager for rebalancer
        vm.prank(users.liquidityProvider);
        nonfungiblePositionManager.approve(address(rebalancer), tokenId);

        uint256 expectedAmountOut;
        {
            uint256 targetRatio = UniswapV3Logic._getTargetRatio(
                position.sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(position.newLowerTick),
                TickMath.getSqrtRatioAtTick(position.newUpperTick)
            );

            (uint256 fee0, uint256 fee1) = getFeeAmounts(tokenId);

            uint256 amount0 = lpVars.amount0 + fee0;
            uint256 amount1 = lpVars.amount1 + fee1;

            uint256 token0ValueInToken1 = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, true, amount0);
            uint256 totalValueInToken1 = amount1 + token0ValueInToken1;
            uint256 currentRatio = amount1.mulDivDown(1e18, totalValueInToken1);

            vm.assume(targetRatio < currentRatio);

            uint256 amountIn = (currentRatio - targetRatio).mulDivDown(totalValueInToken1, 1e18);
            expectedAmountOut = UniswapV3Logic._getAmountOut(position.sqrtPriceX96, false, amountIn);
        }

        // When : calling getSwapParameters
        (bool zeroToOne, uint256 amountOut, int24 tickChange) = rebalancer.getSwapParameters(position, tokenId);

        // Then : It should return correct values
        assertEq(zeroToOne, false);
        // Here we use approxEqRel as the difference between getAmountsForLiquidity() and the effective mint of a new position
        // might slightly differ (we check to max 1% diff)
        // TODO: validate why diff (first do full testing ?)
        //assertApproxEqRel(amountOut, expectedAmountOut, 1e16);
        // TODO : tickChange
    }
}
