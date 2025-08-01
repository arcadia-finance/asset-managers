/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RouterMock } from "../../../utils/mocks/RouterMock.sol";
import { RouterTrampoline } from "../../../../src/cl-managers/RouterTrampoline.sol";
import { RouterTrampoline_Fuzz_Test } from "./_RouterTrampoline.fuzz.t.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";

/**
 * @notice Fuzz tests for the function "execute" of contract "RouterTrampoline".
 */
contract Execute_RouterTrampoline_Fuzz_Test is RouterTrampoline_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RouterTrampoline_Fuzz_Test.setUp();

        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_execute_InsufficientBalance(
        address caller,
        uint64 balanceIn,
        uint64 balanceOut,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: RouterTrampoline has insufficient balance.
        amountIn = uint64(bound(amountIn, 1, type(uint64).max));
        balanceIn = uint64(bound(balanceIn, 0, amountIn - 1));
        deal(address(tokenIn), address(routerTrampoline), balanceIn, true);
        deal(address(tokenOut), address(routerTrampoline), balanceOut, true);

        // When: Calling execute.
        // Then: It should revert.
        bytes memory callData = abi.encodeWithSelector(
            RouterMock.swap.selector, address(tokenIn), address(tokenOut), uint128(amountIn), uint128(amountOut)
        );
        vm.prank(caller);
        vm.expectRevert(bytes(stdError.arithmeticError));
        routerTrampoline.execute(address(routerMock), callData, address(tokenIn), address(tokenOut), amountIn);
    }

    function testFuzz_Revert_execute_RouterReverts(
        address caller,
        uint64 routerBalance,
        uint64 balanceIn,
        uint64 balanceOut,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: RouterTrampoline has sufficient balance.
        amountIn = uint64(bound(amountIn, 0, balanceIn));
        deal(address(tokenIn), address(routerTrampoline), balanceIn, true);
        deal(address(tokenOut), address(routerTrampoline), balanceOut, true);

        // And: Router mock does not have balanceOut.
        amountOut = uint64(bound(amountOut, 1, type(uint64).max));
        routerBalance = uint64(bound(routerBalance, 0, amountOut - 1));
        deal(address(tokenOut), address(routerMock), routerBalance, true);

        // When: Calling execute.
        // Then: It should revert.
        bytes memory callData = abi.encodeWithSelector(
            RouterMock.swap.selector, address(tokenIn), address(tokenOut), uint128(amountIn), uint128(amountOut)
        );
        vm.prank(caller);
        vm.expectRevert(bytes(stdError.arithmeticError));
        routerTrampoline.execute(address(routerMock), callData, address(tokenIn), address(tokenOut), amountIn);
    }

    function testFuzz_Success_execute(
        address caller,
        uint64 routerBalance,
        uint64 balanceIn,
        uint64 balanceOut,
        uint64 amountIn,
        uint64 amountOut
    ) public {
        // Given: Caller is not the routerMock.
        vm.assume(caller != address(routerMock));

        // And: RouterTrampoline has sufficient balance.
        amountIn = uint64(bound(amountIn, 0, balanceIn));
        deal(address(tokenIn), address(routerTrampoline), balanceIn, true);
        deal(address(tokenOut), address(routerTrampoline), balanceOut, true);

        // And: Router mock has sufficient balance.
        amountOut = uint64(bound(amountOut, 0, routerBalance));
        deal(address(tokenOut), address(routerMock), routerBalance, true);

        // When: Calling execute.
        bytes memory callData = abi.encodeWithSelector(
            RouterMock.swap.selector, address(tokenIn), address(tokenOut), uint128(amountIn), uint128(amountOut)
        );
        vm.prank(caller);
        routerTrampoline.execute(address(routerMock), callData, address(tokenIn), address(tokenOut), amountIn);

        // Then: Caller receives the correct amount of tokens.
        assertEq(tokenIn.balanceOf(caller), balanceIn - amountIn);
        assertEq(tokenOut.balanceOf(caller), uint256(balanceOut) + amountOut);
    }
}
