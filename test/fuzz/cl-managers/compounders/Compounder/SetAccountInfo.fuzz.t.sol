/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountVariableVersion } from
    "../../../../../lib/accounts-v2/test/utils/mocks/accounts/AccountVariableVersion.sol";
import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { StdStorage, stdStorage } from "../../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Compounder".
 */
contract SetAccountInfo_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Compounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.setAccountInfo(account_, initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.NotAnAccount.selector);
        compounder.setAccountInfo(account_, initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, "");
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(
        address caller,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio
    ) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the compounder.
        // Then: it should revert.
        vm.prank(caller);
        vm.expectRevert(Compounder.OnlyAccountOwner.selector);
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidAccountVersion(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        uint256 accountVersion
    ) public {
        // Given: Account has an invalid version.
        accountVersion = bound(accountVersion, 0, 2);
        AccountVariableVersion account_ = new AccountVariableVersion(accountVersion, address(factory));
        stdstore.target(address(factory)).sig(factory.isAccount.selector).with_key(address(account_)).checked_write(
            true
        );
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account_)).checked_write(
            2
        );

        // When: Owner calls setInitiator on the compounder.
        // Then: it should revert.
        vm.prank(account_.owner());
        vm.expectRevert(Compounder.InvalidAccountVersion.selector);
        compounder.setAccountInfo(
            address(account_), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidClaimFee(
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
        vm.prank(account.owner());
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidSwapFee(
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
        vm.prank(account.owner());
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidTolerance(
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
        vm.prank(account.owner());
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidMinLiquidityRatio(
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
        vm.prank(account.owner());
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );
    }

    function testFuzz_Success_setAccountInfo(
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
        vm.prank(account.owner());
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, ""
        );

        // Then: Initiator should be set for that Account
        assertEq(compounder.accountToInitiator(account.owner(), address(account)), initiator);

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
