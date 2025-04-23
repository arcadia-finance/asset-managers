/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "YieldClaimer".
 */
contract Constructor_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(
        address factory_,
        address rewardToken,
        address slipstreamPositionManager_,
        address stakedSlipstreamAM_,
        address stakedSlipstreamWrapper,
        address uniswapV3PositionManager,
        address uniswapV4PositionManager,
        address weth,
        uint256 maxInitiatorFee
    ) public {
        vm.prank(users.owner);
        YieldClaimer yieldClaimer_ = new YieldClaimer(
            factory_,
            rewardToken,
            slipstreamPositionManager_,
            stakedSlipstreamAM_,
            stakedSlipstreamWrapper,
            uniswapV3PositionManager,
            uniswapV4PositionManager,
            weth,
            maxInitiatorFee
        );

        assertEq(yieldClaimer_.MAX_INITIATOR_FEE(), maxInitiatorFee);
    }
}
