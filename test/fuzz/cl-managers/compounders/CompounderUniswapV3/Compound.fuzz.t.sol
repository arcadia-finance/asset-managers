/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { CompounderUniswapV3_Fuzz_Test } from "./_CompounderUniswapV3.fuzz.t.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "compound" of contract "CompounderUniswapV3".
 */
contract Compound_CompounderUniswapV3_Fuzz_Test is CompounderUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compound_Paused(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Compounder is Paused.
        vm.prank(users.owner);
        compounder.setPauseFlag(true);

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Guardian.Paused.selector);
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_Reentered(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : account is not address(0)
        vm.assume(account_ != address(0));
        compounder.setAccount(account_);

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.Reentered.selector);
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidAccount(
        address account_,
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given: Account is not an Arcadia Account.
        vm.assume(!factory.isAccount(account_));

        // And: account_ has no owner() function.
        vm.assume(account_.code.length == 0);

        // And: Account is not a precompile.
        vm.assume(account_ > address(20));

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        if (account_.code.length == 0 && !isPrecompile(account_)) {
            vm.expectRevert(abi.encodePacked("call to non-contract address ", vm.toString(account_)));
        } else {
            vm.expectRevert(bytes(""));
        }
        compounder.compound(account_, initiatorParams);
    }

    function testFuzz_Revert_compound_InvalidInitiator(
        Compounder.InitiatorParams memory initiatorParams,
        address caller
    ) public {
        // Given : Caller is not address(0).
        vm.assume(caller != address(0));

        // And : Owner of the account has not set an initiator yet

        // When : calling compound
        // Then : it should revert
        vm.prank(caller);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Revert_compound_ChangeAccountOwnership(
        Compounder.InitiatorParams memory initiatorParams,
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

        // And: Compounder is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Compounder is allowed as Asset Manager by New Owner.
        vm.prank(users.accountOwner);
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));
        vm.startPrank(newOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));
        vm.warp(block.timestamp + 10 minutes);
        factory.safeTransferFrom(newOwner, users.accountOwner, address(account));
        vm.stopPrank();

        // And: The initiator is set.
        // And: Account info is set.
        tolerance = bound(tolerance, 0.01 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When : calling compound
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Success_compound(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);

        // And: uniV3 is allowed.
        deployUniswapV3AM();

        // And: Compounder is allowed as Asset Manager
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(compounder);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

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
        {
            (uint160 sqrtPrice,,,,,,) = poolUniswap.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: liqudity is not 0.
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmounts(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolUniswap.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            // Amounts should be big enough or rounding errors become too big.
            vm.assume(rebalanceParams.amountIn > 1e8);
            vm.assume(rebalanceParams.minLiquidity > 1e8);
        }

        // When: Calling compound().
        initiatorParams.swapData = "";
        vm.prank(initiator);
        compounder.compound(address(account), initiatorParams);

        // Then: The position should be deposited back into the account.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position.id), address(account));
    }
}
