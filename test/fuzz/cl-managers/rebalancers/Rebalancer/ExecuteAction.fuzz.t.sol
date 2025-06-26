/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { HookMock } from "../../../../utils/mocks/HookMock.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "Rebalancer".
 */
contract ExecuteAction_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    HookMock internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();

        strategyHook = new HookMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: account is set.
        rebalancer.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Rebalancer.OnlyAccount.selector);
        rebalancer.executeAction(rebalanceData);
        vm.stopPrank();
    }

    function testFuzz_Revert_executeAction_InvalidClaimFee(
        address initiator,
        Rebalancer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            maxClaimFee,
            maxSwapFee,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            "",
            ""
        );

        // And: claimfee is bigger than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, maxClaimFee + 1, type(uint64).max));

        // And: account is set.
        rebalancer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        address initiator,
        Rebalancer.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            maxClaimFee,
            maxSwapFee,
            MAX_TOLERANCE,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            "",
            ""
        );

        // And: claimfee is smaller than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, maxClaimFee));

        // And: swapFee is bigger than maxSwapFee.
        initiatorParams.swapFee = uint64(bound(initiatorParams.swapFee, maxSwapFee + 1, type(uint64).max));

        // And: account is set.
        rebalancer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.executeAction(actionTargetData);
    }
}
