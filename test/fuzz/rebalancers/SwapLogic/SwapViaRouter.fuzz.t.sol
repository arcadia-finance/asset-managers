/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { SwapLogic_Fuzz_Test } from "./_SwapLogic.fuzz.t.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_swapViaRouter" of contract "SwapLogic".
 */
contract SwapViaRouter_SwapLogic_Fuzz_Test is SwapLogic_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(SwapLogic_Fuzz_Test) {
        SwapLogic_Fuzz_Test.setUp();

        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_swapViaRouter_Router(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has insufficient balance.
        balance0 = uint64(bound(balance0, 0, type(uint64).max - 1));
        amountIn = uint64(bound(amountIn, balance0 + 1, type(uint64).max));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        // Then: It should revert.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        vm.expectRevert(bytes(stdError.arithmeticError));
        swapLogic.swapViaRouter(address(nonfungiblePositionManager), position, true, swapData);
    }

    function testFuzz_Success_swapViaRouter_oneToZero_UniswapV3(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaRouter(address(nonfungiblePositionManager), position, true, swapData);

        // Then: The correct balances are returned.
        assertEq(balance0_, balance0 - amountIn);
        assertEq(balance1_, uint256(balance1) + amountOut);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaRouter_ZeroToOne_UniswapV3(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token0), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token1), address(token0), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaRouter(address(nonfungiblePositionManager), position, false, swapData);

        // Then: The correct balances are returned.
        assertEq(balance0_, uint256(balance0) + amountOut);
        assertEq(balance1_, balance1 - amountIn);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaRouter_oneToZero_Slipstream(
        address positionManager,
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: positionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(nonfungiblePositionManager));

        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolCl);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaRouter(positionManager, position, true, swapData);

        // Then: The correct balances are returned.
        assertEq(balance0_, balance0 - amountIn);
        assertEq(balance1_, uint256(balance1) + amountOut);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }

    function testFuzz_Success_swapViaRouter_ZeroToOne_Slipstream(
        address positionManager,
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: positionManager is not the UniswapV3 Position Manager.
        vm.assume(positionManager != address(nonfungiblePositionManager));

        // Given: A pool with liquidity.
        position.sqrtPriceX96 = bound(position.sqrtPriceX96, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitSlipstream(uint160(position.sqrtPriceX96), liquidityPool);
        position.token0 = address(token0);
        position.token1 = address(token1);
        position.pool = address(poolCl);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));

        // And: Contract has balances..
        deal(address(token0), address(swapLogic), balance0, true);
        deal(address(token1), address(swapLogic), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token0), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token1), address(token0), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        (uint256 balance0_, uint256 balance1_, Rebalancer.PositionState memory position_) =
            swapLogic.swapViaRouter(positionManager, position, false, swapData);

        // Then: The correct balances are returned.
        assertEq(balance0_, uint256(balance0) + amountOut);
        assertEq(balance1_, balance1 - amountIn);

        // And: The sqrtPriceX96 is updated.
        assertEq(position_.sqrtPriceX96, position.sqrtPriceX96);
    }
}
