/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { YieldClaimer } from "../../../../src/yield-claimers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "executeAction" of contract "YieldClaimer".
 */
contract ExecuteAction_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        YieldClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_executeAction_OnlyAccount(address notAccount, address account_) public {
        // Given: Account_ is not notAccount.
        vm.assume(notAccount != account_);

        // And: An account address is defined in storage.
        yieldClaimer.setAccount(account_);

        // When: A not valid address calls executeAction();
        // Then: It should revert.
        vm.prank(notAccount);
        vm.expectRevert(YieldClaimer.OnlyAccount.selector);
        yieldClaimer.executeAction("");
    }

    function testFuzz_Revert_executeAction_InvalidPositionManager(
        address account_,
        address slipstreamPositionManager_,
        address stakedSlipstreamAM_,
        address stakedSlipstreamWrapper_,
        address uniswapV3PositionManager_,
        address uniswapV4PositionManager_,
        address positionManager,
        uint256 tokenId
    ) public {
        // Given: Invalid position manager.
        vm.assume(positionManager != slipstreamPositionManager_);
        vm.assume(positionManager != stakedSlipstreamAM_);
        vm.assume(positionManager != stakedSlipstreamWrapper_);
        vm.assume(positionManager != uniswapV3PositionManager_);
        vm.assume(positionManager != uniswapV4PositionManager_);

        // And: Yield Claimer is deployed.
        deployYieldClaimer(
            address(0),
            slipstreamPositionManager_,
            stakedSlipstreamAM_,
            stakedSlipstreamWrapper_,
            uniswapV3PositionManager_,
            uniswapV4PositionManager_,
            address(0),
            MAX_INITIATOR_FEE_YIELD_CLAIMER
        );

        // And: An account address is defined in storage.
        yieldClaimer.setAccount(account_);

        // When: Calling claim().
        bytes memory claimData = abi.encode(positionManager, tokenId, initiatorYieldClaimer);
        // Then: It should revert.
        vm.prank(account_);
        vm.expectRevert(YieldClaimer.InvalidPositionManager.selector);
        yieldClaimer.executeAction(claimData);
    }

    // All others cases are covered in Claim*.fuzz.t.sol
}
