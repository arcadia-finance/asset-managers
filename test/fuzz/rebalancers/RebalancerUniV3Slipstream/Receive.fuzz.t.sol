/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalancerUniV3Slipstream } from "../../../../src/rebalancers/RebalancerUniV3Slipstream.sol";
import { RebalancerUniV3Slipstream_Fuzz_Test } from "./_Rebalancer2UniV3Slipstream.fuzz.t.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";

/**
 * @notice Fuzz tests for the function "receive" of contract "RebalancerUniV3Slipstream".
 */
contract Receive_RebalancerUniV3Slipstream_Fuzz_Test is RebalancerUniV3Slipstream_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniV3Slipstream_Fuzz_Test) {
        RebalancerUniV3Slipstream_Fuzz_Test.setUp();

        SlipstreamFixture.setUp();
        deployAerodromePeriphery();
        deploySlipstream();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_receive_NonPositionManager(address sender, uint256 value) public {
        vm.assume(sender != address(slipstreamPositionManager));

        deal(sender, value);

        vm.prank(sender);
        (bool success, bytes memory data) = address(rebalancer).call{ value: value }(new bytes(0));

        assertFalse(success);
        assertEq(bytes4(data), RebalancerUniV3Slipstream.OnlyPositionManager.selector);
    }

    function testFuzz_Success_receive(uint256 value) public {
        deal(address(slipstreamPositionManager), value);

        vm.prank(address(slipstreamPositionManager));
        (bool success, bytes memory data) = address(rebalancer).call{ value: value }(new bytes(0));

        assertTrue(success);
        assertEq(data, bytes(""));
    }
}
