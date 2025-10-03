/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../../src/cow-swapper/CowSwapper.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "onSetAssetManager" of contract "CowSwapper".
 */
contract OnSetCowSwapper_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
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
        cowSwapper.setAccount(account_);

        // When: calling onSetAssetManager
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(CowSwapper.Reentered.selector);
        cowSwapper.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_NotAnAccount(
        address account_,
        address accountOwner,
        bool status,
        bytes memory data
    ) public {
        // Given: account_ is not an Arcadia Account.
        vm.assume(account_ != address(account));

        // When: Calling onSetAssetManager.
        // Then: It should revert.
        vm.prank(account_);
        vm.expectRevert(CowSwapper.NotAnAccount.selector);
        cowSwapper.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidValue(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxSwapFee,
        address orderHook,
        bytes calldata hookData,
        bytes calldata metaData
    ) public {
        // Given: maxSwapFee is bigger than 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 1e18 + 1, type(uint64).max));

        // When: Account calls onSetAssetManager.
        // Then: It should revert
        bytes memory data = abi.encode(initiator, maxSwapFee, orderHook, hookData, metaData);
        vm.prank(address(account));
        vm.expectRevert(CowSwapper.InvalidValue.selector);
        cowSwapper.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Success_onSetAssetManager(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxSwapFee,
        bytes calldata metaData
    ) public {
        // Given: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // When: Account calls onSetAssetManager.
        bytes memory data = abi.encode(initiator, maxSwapFee, address(orderHook), abi.encode(bytes("")), metaData);
        vm.prank(address(account));
        cowSwapper.onSetAssetManager(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(cowSwapper.ownerToAccountToInitiator(accountOwner, address(account)), initiator);
        (uint64 maxSwapFee_, address orderHook) = cowSwapper.accountInfo(address(account));
        assertEq(maxSwapFee_, maxSwapFee);
        assertEq(orderHook, address(orderHook));
        assertEq(cowSwapper.metaData(address(account)), metaData);
    }
}
