/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { FixedPointMathLib } from "../../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { HookMock } from "../../../../utils/mocks/HookMock.sol";
import { Rebalancer } from "../../../../../src/cl-managers/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setAccountInfo" of contract "Rebalancer".
 */
contract SetAccountInfo_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
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
    function testFuzz_Revert_setAccountInfo_Reentered(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook,
        bytes calldata strategyData
    ) public {
        // Given: Account is set.
        vm.assume(account_ != address(0));
        rebalancer.setAccount(account_);

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.Reentered.selector);
        rebalancer.setAccountInfo(
            account_, initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, strategyData, ""
        );
    }

    function testFuzz_Revert_setAccountInfo_NotAnAccount(
        address caller,
        address account_,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: account is not an Arcadia Account
        vm.assume(account_ != address(account));

        // When: calling rebalance
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.NotAnAccount.selector);
        rebalancer.setAccountInfo(
            account_, initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Revert_setAccountInfo_OnlyAccountOwner(
        address caller,
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: caller is not the Arcadia Account owner.
        vm.assume(caller != account.owner());

        // When: A random address calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(caller);
        vm.expectRevert(Rebalancer.OnlyAccountOwner.selector);
        rebalancer.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidClaimFee(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: Invalid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidSwapFee(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Invalid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidTolerance(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Invalid tolerance.
        tolerance = uint64(bound(tolerance, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Revert_setAccountInfo_InvalidMinLiquidityRatio(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        address hook
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Valid tolerance.
        tolerance = uint64(bound(tolerance, 0, 1e18));

        // And: Invalid minLiquidityRatio.
        minLiquidityRatio = uint64(bound(minLiquidityRatio, 1e18 + 1, type(uint64).max));

        // When: Owner calls setInitiator on the rebalancer
        // Then: it should revert
        vm.prank(account.owner());
        vm.expectRevert(Rebalancer.InvalidValue.selector);
        rebalancer.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, tolerance, minLiquidityRatio, hook, "", ""
        );
    }

    function testFuzz_Success_setAccountInfo(
        address initiator,
        uint256 maxClaimFee,
        uint256 maxSwapFee,
        uint256 tolerance,
        uint256 minLiquidityRatio,
        bytes calldata strategyData
    ) public {
        // Given: Valid claim fee.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: Valid swap fee.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Valid tolerance.
        tolerance = uint64(bound(tolerance, 0, 1e18));

        // And: Valid minLiquidityRatio.
        minLiquidityRatio = uint64(bound(minLiquidityRatio, 0, 1e18));

        // When: Owner calls setInitiator on the rebalancer
        // Then: It should call the hook.
        vm.expectCall(address(strategyHook), abi.encodeCall(strategyHook.setStrategy, (address(account), strategyData)));
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account),
            initiator,
            maxClaimFee,
            maxSwapFee,
            tolerance,
            minLiquidityRatio,
            address(strategyHook),
            strategyData,
            ""
        );

        // Then: Initiator should be set for that Account
        assertEq(rebalancer.accountToInitiator(account.owner(), address(account)), initiator);

        // And: Correct values should be set.
        (
            uint256 maxClaimFee_,
            uint256 maxSwapFee_,
            uint256 upperSqrtPriceDeviation,
            uint256 lowerSqrtPriceDeviation,
            uint256 minLiquidityRatio_,
            address strategyHook_
        ) = rebalancer.accountInfo(address(account));
        assertEq(maxClaimFee_, maxClaimFee);
        assertEq(maxSwapFee_, maxSwapFee);
        assertEq(upperSqrtPriceDeviation, FixedPointMathLib.sqrt((1e18 + tolerance) * 1e18));
        assertEq(lowerSqrtPriceDeviation, FixedPointMathLib.sqrt((1e18 - tolerance) * 1e18));
        assertEq(minLiquidityRatio_, minLiquidityRatio);
        assertEq(strategyHook_, address(strategyHook));
    }
}
