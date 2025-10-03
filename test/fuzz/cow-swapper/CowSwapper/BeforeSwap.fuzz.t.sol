/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";

/**
 * @notice Fuzz tests for the function "beforeSwap" of contract "CowSwapper".
 */
contract BeforeSwap_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    using GPv2Order for GPv2Order.Data;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_OnlyHooksTrampoline(address caller, bytes calldata initiatorData) public {
        // Given : Caller is not the hooks trampoline.
        vm.assume(caller != address(hooksTrampoline));

        // When : calling beforeSwap.
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(CowSwapper.OnlyHooksTrampoline.selector);
        cowSwapper.beforeSwap(initiatorData);
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        address initiator,
        uint64 maxSwapFee,
        uint64 swapFee,
        GPv2Order.Data memory order
    ) public {
        // Given: Invalid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));
        swapFee = uint64(bound(swapFee, maxSwapFee + 1, type(uint64).max));
        vm.prank(users.accountOwner);
        cowSwapper.setAccountInfo(address(account), initiator, maxSwapFee, address(orderHook), abi.encode(""), "");

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        // When: Hooks trampoline calls beforeSwap.
        // Then: it should revert.
        vm.prank(address(hooksTrampoline));
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        cowSwapper.beforeSwap(abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee));
    }

    function testFuzz_Success_executeAction(
        address initiator,
        uint64 maxSwapFee,
        uint64 swapFee,
        GPv2Order.Data memory order
    ) public {
        // Given: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));
        swapFee = uint64(bound(swapFee, 0, maxSwapFee));
        vm.prank(users.accountOwner);
        cowSwapper.setAccountInfo(address(account), initiator, maxSwapFee, address(orderHook), abi.encode(""), "");

        // And: Valid order.
        givenValidOrder(swapFee, order);

        // And: Transient state is set.
        cowSwapper.setAccount(address(account));
        cowSwapper.setInitiator(initiator);
        cowSwapper.setTokenIn(address(order.sellToken));
        cowSwapper.setAmountIn(order.sellAmount);

        // When: Hooks trampoline calls beforeSwap.
        vm.prank(address(hooksTrampoline));
        cowSwapper.beforeSwap(abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee));

        // Then: Transient state is set.
        assertEq(cowSwapper.getTokenOut(), address(order.buyToken));
        assertEq(cowSwapper.getAmountOut(), order.buyAmount);
        assertEq(cowSwapper.getSwapFee(), swapFee);
        assertEq(cowSwapper.getTokenIn(), address(order.sellToken));
        assertEq(cowSwapper.getOrderHash(), order.hash(orderHook.DOMAIN_SEPARATOR()));
        assertEq(
            cowSwapper.getMessageHash(),
            keccak256(abi.encode(address(account), swapFee, order.hash(orderHook.DOMAIN_SEPARATOR())))
        );
    }
}
