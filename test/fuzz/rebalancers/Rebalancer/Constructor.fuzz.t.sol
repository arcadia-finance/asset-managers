/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";
import { RebalancerExtension } from "../../../utils/extensions/RebalancerExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Rebalancer".
 */
contract Constructor_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxInitiatorFee,
        uint256 maxSlippageRatio
    ) public {
        vm.prank(users.owner);
        RebalancerExtension rebalancer_ =
            new RebalancerExtension(arcadiaFactory, maxTolerance, maxInitiatorFee, maxSlippageRatio);

        assertEq(address(rebalancer_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(rebalancer_.MAX_TOLERANCE(), maxTolerance);
        assertEq(rebalancer_.MAX_INITIATOR_FEE(), maxInitiatorFee);
        assertEq(rebalancer_.MIN_LIQUIDITY_RATIO(), maxSlippageRatio);
    }
}
