/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";
import { stdError } from "../../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapHelpers } from "../../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_swapViaRouter" of contract "Compounder".
 */
contract SwapViaRouter_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(Compounder_Fuzz_Test) {
        Compounder_Fuzz_Test.setUp();

        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_swapViaRouter_RouterReverts(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPrice = bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPrice), liquidityPool);
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Router mock does not have balanceOut.
        amountOut = uint64(bound(amountOut, 1, type(uint64).max));

        // When: Calling swapViaRouter.
        // Then: It should revert.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        vm.expectRevert(bytes(stdError.arithmeticError));
        compounder.swapViaRouter(balances, position, true, swapData);
    }

    function testFuzz_Success_swapViaRouter_ZeroToOne(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPrice = bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPrice), liquidityPool);
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        balances = compounder.swapViaRouter(balances, position, true, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], balance0 - amountIn);
        assertEq(balances[1], uint256(balance1) + amountOut);
    }

    function testFuzz_Success_swapViaRouter_OneToZero(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        position.sqrtPrice = bound(position.sqrtPrice, BOUND_SQRT_PRICE_LOWER * 1e3, BOUND_SQRT_PRICE_UPPER / 1e3);
        liquidityPool =
            uint128(bound(liquidityPool, UniswapHelpers.maxLiquidity(1) / 1000, UniswapHelpers.maxLiquidity(1) / 10));
        deployAndInitUniswapV3(uint160(position.sqrtPrice), liquidityPool);
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
        position.pool = address(poolUniswap);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances..
        deal(address(token0), address(compounder), balance0, true);
        deal(address(token1), address(compounder), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token0), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token1), address(token0), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        balances = compounder.swapViaRouter(balances, position, false, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], uint256(balance0) + amountOut);
        assertEq(balances[1], balance1 - amountIn);
    }
}
