/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";

/**
 * @notice Fuzz tests for the function "getMessageHash" of contract "CowSwapper".
 */
contract GetMessageHash_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
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

    function testFuzz_Success_getMessageHash(address account_, uint64 swapFee_, bytes32 orderHash_) public view {
        bytes32 messageHash = cowSwapper.getMessageHash(account_, swapFee_, orderHash_);

        assertTrue(messageHash != bytes32(0));
    }

    function testFuzz_Success_getMessageHash_Deterministic(address account_, uint64 swapFee_, bytes32 orderHash_)
        public
        view
    {
        bytes32 messageHash1 = cowSwapper.getMessageHash(account_, swapFee_, orderHash_);
        bytes32 messageHash2 = cowSwapper.getMessageHash(account_, swapFee_, orderHash_);

        assertEq(messageHash1, messageHash2);
    }

    function testFuzz_Success_getMessageHash_DifferentAccount(
        address account1,
        address account2,
        uint64 swapFee_,
        bytes32 orderHash_
    ) public view {
        vm.assume(account1 != account2);

        assertNotEq(
            cowSwapper.getMessageHash(account1, swapFee_, orderHash_),
            cowSwapper.getMessageHash(account2, swapFee_, orderHash_)
        );
    }

    function testFuzz_Success_getMessageHash_DifferentSwapFee(
        address account_,
        uint64 swapFee1,
        uint64 swapFee2,
        bytes32 orderHash_
    ) public view {
        vm.assume(swapFee1 != swapFee2);

        assertNotEq(
            cowSwapper.getMessageHash(account_, swapFee1, orderHash_),
            cowSwapper.getMessageHash(account_, swapFee2, orderHash_)
        );
    }

    function testFuzz_Success_getMessageHash_DifferentOrderHash(
        address account_,
        uint64 swapFee_,
        bytes32 orderHash1,
        bytes32 orderHash2
    ) public view {
        vm.assume(orderHash1 != orderHash2);

        assertNotEq(
            cowSwapper.getMessageHash(account_, swapFee_, orderHash1),
            cowSwapper.getMessageHash(account_, swapFee_, orderHash2)
        );
    }

    function testFuzz_Success_getMessageHash_FromInitiatorData(
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

        // When: Getting the message hash from initiator data.
        bytes memory initiatorData = abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee);
        bytes32 messageHashFromData =
            cowSwapper.getMessageHash(address(account), address(order.sellToken), order.sellAmount, initiatorData);

        // Then: It matches the message hash from explicit parameters.
        bytes32 orderHash_ = order.hash(orderHook.DOMAIN_SEPARATOR());
        bytes32 messageHashFromParams = cowSwapper.getMessageHash(address(account), swapFee, orderHash_);

        assertEq(messageHashFromData, messageHashFromParams);
    }
}
