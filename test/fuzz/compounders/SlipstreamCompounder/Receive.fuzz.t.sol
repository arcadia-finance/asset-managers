/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";

/**
 * @notice Fuzz tests for the function "receive" of contract "SlipstreamCompounder".
 */
contract Receive_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_receive_NonPositionManager(address sender, uint256 value) public {
        vm.assume(sender != address(slipstreamPositionManager));

        deal(sender, value);

        vm.prank(sender);
        (bool success, bytes memory data) = address(compounder).call{ value: value }(new bytes(0));

        assertFalse(success);
        assertEq(bytes4(data), SlipstreamCompounder.OnlyPositionManager.selector);
    }

    function testFuzz_Success_receive(uint256 value) public {
        deal(address(slipstreamPositionManager), value);

        vm.prank(address(slipstreamPositionManager));
        (bool success, bytes memory data) = address(compounder).call{ value: value }(new bytes(0));

        assertTrue(success);
        assertEq(data, bytes(""));
    }
}
