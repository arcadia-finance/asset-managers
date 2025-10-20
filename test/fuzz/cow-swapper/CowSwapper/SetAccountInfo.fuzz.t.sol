/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    AccountVariableVersion
} from "../../../../lib/accounts-v2/test/utils/mocks/accounts/AccountVariableVersion.sol";
import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "CowSwapper".
 */
contract SetAccountInfo_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        cowSwapper.setAccount(account_);

        // When: calling setAccountInfo.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.setAccountInfo(account_, initiator, maxSwapFee, orderHook, hookData, metaData);
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData
    ) public {
        // Given: account is not an Arcadia Account.
        vm.assume(account_ != address(account));

        // When: calling setAccountInfo.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(CowSwapper.NotAnAccount.selector);
        cowSwapper.setAccountInfo(account_, initiator, maxSwapFee, orderHook, hookData, metaData);
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(
        address caller,
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData
    ) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setAccountInfo on the cowSwapper
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(CowSwapper.OnlyAccountOwner.selector);
        cowSwapper.setAccountInfo(address(account), initiator, maxSwapFee, orderHook, hookData, metaData);
    }

    function testFuzz_Revert_setAccountInfo_InvalidAccountVersion(
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData,
        uint256 accountVersion
    ) public {
        // Given: Account has an invalid version.
        accountVersion = bound(accountVersion, 0, 2);
        AccountVariableVersion account_ = new AccountVariableVersion(accountVersion, address(factory));
        stdstore.target(address(factory)).sig(factory.isAccount.selector).with_key(address(account_))
            .checked_write(true);
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account_))
            .checked_write(2);

        // When: Owner calls setAccountInfo on the cowSwapper.
        // Then: it should revert.
        vm.prank(account_.owner());
        vm.expectRevert(CowSwapper.InvalidAccountVersion.selector);
        cowSwapper.setAccountInfo(address(account_), initiator, maxSwapFee, orderHook, hookData, metaData);
    }

    function testFuzz_Revert_setAccountInfo_InvalidValue(
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData
    ) public {
        // Given: maxSwapFee is bigger than 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setAccountInfo.
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        cowSwapper.setAccountInfo(address(account), initiator, maxSwapFee, orderHook, hookData, metaData);
    }

    function testFuzz_Success_setAccountInfo(address initiator, uint256 maxSwapFee, bytes calldata metaData) public {
        // Given: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // When: Owner calls setAccountInfo on the cowSwapper
        vm.prank(account.owner());
        cowSwapper.setAccountInfo(
            address(account), initiator, maxSwapFee, address(orderHook), abi.encode(bytes("")), metaData
        );

        // Then: Initiator should be set for that Account
        assertEq(cowSwapper.ownerToAccountToInitiator(account.owner(), address(account)), initiator);
        (uint64 maxSwapFee_, address hook) = cowSwapper.accountInfo(address(account));
        assertEq(maxSwapFee_, maxSwapFee);
        assertEq(hook, address(orderHook));
        assertEq(cowSwapper.metaData(address(account)), metaData);
    }
}
