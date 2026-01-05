/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import {
    AccountVariableVersion
} from "../../../../../lib/accounts-v2/test/utils/mocks/accounts/AccountVariableVersion.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Closer".
 */
contract SetAccountInfo_Closer_Fuzz_Test is Closer_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        closer.setAccount(account_);

        // When: calling setAccountInfo
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Closer.Reentered.selector);
        closer.setAccountInfo(account_, initiator, maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling setAccountInfo
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Closer.NotAnAccount.selector);
        closer.setAccountInfo(account_, initiator, maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(address caller, address initiator, uint256 maxClaimFee)
        public
    {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the closer.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(Closer.OnlyAccountOwner.selector);
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_InvalidAccountVersion(
        address initiator,
        uint256 maxClaimFee,
        uint256 accountVersion
    ) public {
        // Given: Account has an invalid version.
        accountVersion = bound(accountVersion, 0, 2);
        AccountVariableVersion account_ = new AccountVariableVersion(accountVersion, address(factory));
        stdstore.target(address(factory)).sig(factory.isAccount.selector).with_key(address(account_))
            .checked_write(true);
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account_))
            .checked_write(2);

        // When: Owner calls setInitiator on the closer.
        // Then: it should revert.
        vm.prank(account_.owner());
        vm.expectRevert(Closer.InvalidAccountVersion.selector);
        closer.setAccountInfo(address(account_), initiator, maxClaimFee, "");
    }

    function testFuzz_Revert_setAccountInfo_InvalidClaimFee(address initiator, uint256 maxClaimFee) public {
        // Given: Invalid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the closer.
        // Then: it should revert.
        vm.prank(account.owner());
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");
    }

    function testFuzz_Success_setAccountInfo(address initiator, uint256 maxClaimFee) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // When: Owner calls setInitiator on the closer
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, maxClaimFee, "");

        // Then: Initiator should be set for that Account
        assertEq(closer.accountToInitiator(account.owner(), address(account)), initiator);

        // And: Correct values should be set.
        (uint256 maxClaimFee_) = closer.accountInfo(address(account));
        assertEq(maxClaimFee_, maxClaimFee);
    }
}
