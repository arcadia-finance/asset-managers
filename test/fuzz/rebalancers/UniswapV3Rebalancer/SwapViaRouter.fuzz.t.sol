/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { ISwapRouter02 } from
    "../../../../lib/accounts-v2/test/utils/fixtures/swap-router-02/interfaces/ISwapRouter02.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { SwapMath } from "../../../../src/rebalancers/libraries/SwapMath.sol";
import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "SwapViaRouter" of contract "UniswapV3Rebalancer".
 */
contract SwapViaRouter_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
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

    function testFuzz_Revert_swapViaRouter_oneToZero_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given : oneToZero swapViaRouter
        bool zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
                rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        {
            // Bring pool to unbalanced state
            // Take 0,1% sqrtPrice above upperBound target to be sure we exceed it
            uint256 sqrtPriceX96Target =
                position.upperBoundSqrtPriceX96 + ((position.upperBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

            int256 amountRemaining = int256(type(int128).max);
            // Calculate the minimum amount of token 1 to swapViaRouter to achieve target price
            (, uint256 amountIn_,,) = SwapMath.computeSwapStep(
                sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
            );

            // Do the swapViaRouter.
            vm.startPrank(users.swapper);
            deal(address(token1), users.swapper, type(uint128).max);

            token1.approve(address(swapRouter), type(uint128).max);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams;
            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                fee: uniV3Pool.fee(),
                recipient: users.swapper,
                amountIn: amountIn_,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
            vm.stopPrank();
        }

        // Send token1 (amountIn) to rebalancer for swapViaRouter
        deal(address(token1), address(rebalancer), amountIn);
        // Send token0 (amountOut) to router for swapViaRouter
        deal(address(token0), address(routerMock), amountOut);

        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), amountIn, amountOut);
        bytes memory swapData = abi.encode(address(routerMock), routerData);

        // When : calling swapViaRouter
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.UnbalancedPool.selector);
        rebalancer.swapViaRouter(position, zeroToOne, amountIn, swapData);
    }

    function testFuzz_Revert_swapViaRouter_zeroToOne_UnbalancedPool(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given : zeroToOne swapViaRouter
        bool zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();
        uint128 liquidity = uniV3Pool.liquidity();

        {
            (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
                rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        {
            // Take 0,1% sqrtPrice below lowerBound target to be sure we exceed it
            uint256 sqrtPriceX96Target =
                position.lowerBoundSqrtPriceX96 - ((position.lowerBoundSqrtPriceX96 * (0.001 * 1e18)) / 1e18);

            int256 amountRemaining = type(int128).max;
            // Calculate the minimum amount of token 0 to swapViaRouter to achieve target price
            (, uint256 amountIn_,,) = SwapMath.computeSwapStep(
                sqrtPriceX96, uint160(sqrtPriceX96Target), liquidity, amountRemaining, 100 * POOL_FEE
            );

            // Do the swapViaRouter.
            vm.startPrank(users.swapper);
            deal(address(token0), users.swapper, type(uint128).max);

            token0.approve(address(swapRouter), type(uint128).max);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams;
            exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: uniV3Pool.fee(),
                recipient: users.swapper,
                amountIn: amountIn_,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);
            vm.stopPrank();
        }

        // Send token0 (amountIn) to rebalancer for swapViaRouter
        deal(address(token0), address(rebalancer), amountIn);
        // Send token1 (amountOut) to router for swapViaRouter
        deal(address(token1), address(routerMock), amountOut);

        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), amountIn, amountOut);
        bytes memory swapData = abi.encode(address(routerMock), routerData);

        // When : calling swapViaRouter
        // Then : it should revert
        vm.expectRevert(UniswapV3Rebalancer.UnbalancedPool.selector);
        rebalancer.swapViaRouter(position, zeroToOne, amountIn, swapData);
    }

    function testFuzz_Success_swapViaRouter_oneToZero(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given : oneToZero swapViaRouter
        bool zeroToOne = false;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        {
            (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
                rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Send token1 (amountIn) to rebalancer for swapViaRouter
        deal(address(token1), address(rebalancer), amountIn);
        // Send token0 (amountOut) to router for swapViaRouter
        deal(address(token0), address(routerMock), amountOut);

        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, address(token1), address(token0), amountIn, amountOut);
        bytes memory swapData = abi.encode(address(routerMock), routerData);

        // When : calling swapViaRouter
        rebalancer.swapViaRouter(position, zeroToOne, amountIn, swapData);

        // Then : Tokens should have been transferred
        assertEq(token0.balanceOf(address(rebalancer)), amountOut);
        assertEq(token1.balanceOf(address(routerMock)), amountIn);
    }

    function testFuzz_Success_swapViaRouter_zeroToOne(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        UniswapV3Rebalancer.PositionState memory position,
        uint128 amountIn,
        uint128 amountOut
    ) public {
        // Given : zeroToOne swapViaRouter
        bool zeroToOne = true;

        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);
        // Get the current pool state
        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        {
            (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
                rebalancer.initiatorInfo(initVars.initiator);
            position.token0 = address(token0);
            position.token1 = address(token1);
            position.upperBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(upperSqrtPriceDeviation, 1e18);
            position.lowerBoundSqrtPriceX96 = uint256(sqrtPriceX96).mulDivDown(lowerSqrtPriceDeviation, 1e18);
            position.pool = address(uniV3Pool);
        }

        // Send token0 (amountIn) to rebalancer for swapViaRouter
        deal(address(token0), address(rebalancer), amountIn);
        // Send token1 (amountOut) to router for swapViaRouter
        deal(address(token1), address(routerMock), amountOut);

        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, address(token0), address(token1), amountIn, amountOut);
        bytes memory swapData = abi.encode(address(routerMock), routerData);

        // When : calling swapViaRouter
        rebalancer.swapViaRouter(position, zeroToOne, amountIn, swapData);

        // Then : Tokens should have been transferred
        assertEq(token1.balanceOf(address(rebalancer)), amountOut);
        assertEq(token0.balanceOf(address(routerMock)), amountIn);
    }
}
