/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { DefaultHook } from "../../../../utils/mocks/DefaultHook.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "Rebalancer".
 */
contract Rebalance_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();

        strategyHook = new DefaultHook();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalance_Paused(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Rebalancer is Paused.
        vm.prank(users.owner);
        rebalancer.setPauseFlag(true);

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_Reentered(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_InvalidAccount(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalance_InvalidInitiator(
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.InvalidInitiator.selector);
        rebalancer.rebalance(address(account), initiatorParams);
    }

    function testFuzz_Revert_rebalance_ChangeAccountOwnership(
        Rebalancer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator,
        uint256 tolerance
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Rebalancer is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And: Rebalancer is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(rebalancer), true);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            MAX_FEE,
            MAX_FEE,
            tolerance,
            MIN_LIQUIDITY_RATIO,
            address(strategyHook),
            abi.encode(address(token0), address(token1), ""),
            ""
        );

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Account is transferred to newOwner.
        vm.startPrank(account.owner());
        factory.safeTransferFrom(account.owner(), newOwner, address(account));
        vm.stopPrank();

        // When : calling rebalance
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Rebalancer.InvalidInitiator.selector);
        rebalancer.rebalance(address(account), initiatorParams);
    }
}
