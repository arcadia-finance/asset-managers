/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { HookMock } from "../../../utils/mocks/HookMock.sol";
import { IWETH } from "../../../../src/rebalancers/interfaces/IWETH.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_swapViaRouter" of contract "RebalancerUniswapV4".
 */
contract SwapViaRouter_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    HookMock internal strategyHook;
    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniswapV4_Fuzz_Test) {
        RebalancerUniswapV4_Fuzz_Test.setUp();

        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_swapViaRouter_InvalidRouter(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        bool zeroToOne,
        bytes memory data,
        address initiator,
        bytes memory strategyData
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);

        // And: Contract has insufficient balance.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Hook is set.
        strategyHook = new HookMock();
        vm.prank(account.owner());
        rebalancer.setAccountInfo(address(account), initiator, address(strategyHook), strategyData);

        // And: Contract has balances..
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Hook is set as router.
        bytes memory swapData = abi.encode(address(strategyHook), uint256(amountIn), data);

        // When: Calling swapViaRouter.
        // Then: It should revert.
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InvalidRouter.selector);
        rebalancer.swapViaRouter(balances, position, zeroToOne, swapData);
    }

    function testFuzz_Revert_swapViaRouter_RouterReverts(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);

        // And: Contract has insufficient balance.
        balance0 = uint64(bound(balance0, 0, type(uint64).max - 1));
        amountIn = uint64(bound(amountIn, balance0 + 1, type(uint64).max));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances..
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        // Then: It should revert.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        vm.expectRevert(bytes(stdError.arithmeticError));
        rebalancer.swapViaRouter(balances, position, true, swapData);
    }

    function testFuzz_Success_swapViaRouter_NotNative_ZeroToOne(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances..
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token0), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaRouter(balances, position, true, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], balance0 - amountIn);
        assertEq(balances[1], uint256(balance1) + amountOut);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPrice is updated.
        (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPrice, position_.sqrtPrice);
    }

    function testFuzz_Success_swapViaRouter_NotNative_OneToZero(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances..
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token0), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token1), address(token0), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaRouter(balances, position, false, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], uint256(balance0) + amountOut);
        assertEq(balances[1], balance1 - amountIn);
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
        // And: The sqrtPrice is updated.
        (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPrice, position_.sqrtPrice);
    }

    function testFuzz_Success_swapViaRouter_IsNative_ZeroToOne(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);

        // And: Contract has sufficient balance.
        balance0 = uint64(bound(balance0, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance0));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances.
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Router mock has balanceOut.
        deal(address(token1), address(routerMock), amountOut, true);

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(weth9), address(token1), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaRouter(balances, position, true, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], balance0 - amountIn);
        assertEq(balances[1], uint256(balance1) + amountOut);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPrice is updated.
        (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPrice, position_.sqrtPrice);
    }

    function testFuzz_Success_swapViaRouter_IsNative_OneToZero(
        uint128 liquidityPool,
        Rebalancer.PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: A pool with liquidity.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);

        // And: Contract has sufficient balance.
        balance1 = uint64(bound(balance1, 1, type(uint64).max));
        amountIn = uint64(bound(amountIn, 1, balance1));
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;

        // And: Contract has balances..
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // And: Router mock has balanceOut.
        vm.deal(address(routerMock), amountOut);
        vm.prank(address(routerMock));
        IWETH(address(weth9)).deposit{ value: amountOut }();

        // When: Calling swapViaRouter.
        bytes memory data = abi.encodeWithSelector(
            RouterMock.swap.selector, address(token1), address(weth9), uint128(amountIn), uint128(amountOut)
        );
        bytes memory swapData = abi.encode(address(routerMock), uint256(amountIn), data);
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.swapViaRouter(balances, position, false, swapData);

        // Then: The correct balances are returned.
        assertEq(balances[0], uint256(balance0) + amountOut);
        assertEq(balances[1], balance1 - amountIn);
        assertEq(balances[0], address(rebalancer).balance);
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: The sqrtPrice is updated.
        (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
        assertEq(sqrtPrice, position_.sqrtPrice);
    }
}
