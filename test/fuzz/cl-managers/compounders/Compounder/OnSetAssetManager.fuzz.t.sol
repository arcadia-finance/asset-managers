/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";

/**
 * @notice Fuzz tests for the function "onSetAssetManager" of contract "Compounder".
 */
contract OnSetAssetManager_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
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
        compounder.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
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

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.NotAnAccount.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidClaimFee(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Invalid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        bytes memory data = abi.encode(initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidSwapFee(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Invalid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        bytes memory data = abi.encode(initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidTolerance(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Invalid tolerance.
        tolerance = uint64(bound(tolerance, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        bytes memory data = abi.encode(initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Revert_onSetAssetManager_InvalidMinLiquidityRatio(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Valid tolerance.
        tolerance = uint64(bound(tolerance, 0, 1e18));

        // And: Invalid minLiquidityRatio.
        minLiquidityRatio = uint64(bound(minLiquidityRatio, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        bytes memory data = abi.encode(initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.onSetAssetManager(accountOwner, status, data);
    }

    function testFuzz_Success_onSetAssetManager(
        address accountOwner,
        bool status,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Valid tolerance.
        tolerance = uint64(bound(tolerance, 0, 1e18));

        // And: Valid minLiquidityRatio.
        minLiquidityRatio = uint64(bound(minLiquidityRatio, 0, 1e18));

        // When: Owner calls setInitiator on the compounder
        bytes memory data = abi.encode(initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
        vm.prank(address(account));
        compounder.onSetAssetManager(accountOwner, status, data);

        // Then: Initiator should be set for that Account
        assertEq(compounder.accountToInitiator(accountOwner, address(account)), initiator);

        // And: Correct values should be set.
        (
            uint256 maxClaimFee_,
            uint256 maxSwapFee_,
            uint256 upperSqrtPriceDeviation,
            uint256 lowerSqrtPriceDeviation,
            uint256 minLiquidityRatio_
        ) = compounder.accountInfo(address(account));
        assertEq(maxClaimFee_, maxClaimFee);
        assertEq(maxSwapFee_, maxSwapFee);
        assertEq(upperSqrtPriceDeviation, FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));
        assertEq(lowerSqrtPriceDeviation, FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18));
        assertEq(minLiquidityRatio_, minLiquidityRatio);
    }
}
