/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "onSetAssetManager" of contract "Closer".
 */
contract OnSetAssetManager_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_onSetAssetManager_Reentered(
        address caller,
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        closer.setAccount(account_);

        // When: calling onSetAssetManager
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Closer.Reentered.selector);
        closer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_NotAnAccount(
        address caller,
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling onSetAssetManager
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Closer.NotAnAccount.selector);
        closer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidClaimFee(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee
    ) public {
        // Given: Invalid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the closer.
        // Then: it should revert.
        bytes memory data = abi.encode(initiator, maxClaimFee, "");
        vm.prank(address(account));
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Success_onSetAssetManager(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // When: Owner calls setInitiator on the closer
        bytes memory data = abi.encode(initiator, maxClaimFee, "");
        vm.prank(address(account));
        closer.onSetAssetManager(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(closer.accountToInitiator(accountOwner, address(account)), initiator);

        // And: Correct values should be set.
        (uint256 maxClaimFee_) = closer.accountInfo(address(account));
        assertEq(maxClaimFee_, maxClaimFee);
    }
}
