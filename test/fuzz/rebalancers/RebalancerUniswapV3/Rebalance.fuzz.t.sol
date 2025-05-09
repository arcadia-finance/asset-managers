/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { DefaultHook } from "../../../utils/mocks/DefaultHook.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV3_Fuzz_Test } from "./_RebalancerUniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "rebalance" of contract "RebalancerUniswapV3".
 */
contract Rebalance_RebalancerUniswapV3_Fuzz_Test is RebalancerUniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV3_Fuzz_Test.setUp();

        strategyHook = new DefaultHook();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_rebalancePosition_Reentered(
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

    function testFuzz_Revert_rebalancePosition_InvalidAccount(
        address account_,
        Rebalancer.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // When : calling rebalance
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(bytes(""));
        rebalancer.rebalance(account_, initiatorParams);
    }

    function testFuzz_Revert_rebalancePosition_InvalidInitiator(
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

    function testFuzz_Revert_rebalancePosition_ChangeAccountOwnership(
        Rebalancer.InitiatorParams memory initiatorParams,
        address newOwner,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));

        // And: Rebalancer is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And: Rebalancer is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(rebalancer), true);

        // And: The initiator is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0.001 * 1e18, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account), initiator, address(strategyHook), abi.encode(address(token0), address(token1), "")
        );

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

    function testFuzz_Success_rebalancePosition(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        int24 tickLower,
        int24 tickUpper,
        address initiator,
        uint256 tolerance,
        uint256 fee
    ) public {
        // Given: A valid position in range (has both tokens).
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e20));
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.oldId = uint96(position.id);

        // And: uniV3 is allowed.
        deployUniswapV3AM();

        // And: Rebalancer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(rebalancer), true);

        // And: The initiator is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        fee = bound(fee, 0.001 * 1e18, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        rebalancer.setInitiatorInfo(tolerance, fee, MIN_LIQUIDITY_RATIO);
        vm.prank(account.owner());
        rebalancer.setAccountInfo(
            address(account), initiator, address(strategyHook), abi.encode(address(token0), address(token1), "")
        );

        // And: A valid new position.
        tickLower = int24(bound(tickLower, BOUND_TICK_LOWER, BOUND_TICK_UPPER - 10_000));
        tickLower = tickLower / position.tickSpacing * position.tickSpacing;
        tickUpper = int24(bound(tickUpper, tickLower + 10_000, BOUND_TICK_UPPER));
        tickUpper = tickUpper / position.tickSpacing * position.tickSpacing;
        initiatorParams.strategyData = abi.encode(tickLower, tickUpper);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, type(uint8).max));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, type(uint8).max));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(
            users.liquidityProvider, users.accountOwner, position.id
        );
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(nonfungiblePositionManager);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        initiatorParams.trustedSqrtPrice = position.sqrtPrice;

        // When: Calling rebalance().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        rebalancer.rebalance(address(account), initiatorParams);

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position.id + 1), address(account));
    }
}
