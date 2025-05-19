/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../src/compounders/Compounder.sol";
import { CompounderUniswapV4_Fuzz_Test } from "./_CompounderUniswapV4.fuzz.t.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { IWETH } from "../../../../src/interfaces/IWETH.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../src/libraries/RebalanceLogic.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "compound" of contract "CompounderUniswapV4".
 */
contract Rebalance_CompounderUniswapV4_Fuzz_Test is CompounderUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
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
        vm.expectRevert(bytes(""));
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
        address initiator
    ) public canReceiveERC721(newOwner) {
        // Given : newOwner is not the old owner.
        vm.assume(newOwner != account.owner());
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != address(account));

        // And : initiator is not address(0).
        vm.assume(initiator != address(0));

        // And: Compounder is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounder), true);

        // And: Compounder is allowed as Asset Manager by New Owner.
        vm.prank(newOwner);
        account.setAssetManager(address(compounder), true);

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = 0;
        initiatorParams.swapFee = 0;

        // And: Account is transferred to newOwner.
        vm.startPrank(account.owner());
        factory.safeTransferFrom(account.owner(), newOwner, address(account));
        vm.stopPrank();

        // When : calling compound
        // Then : it should revert
        vm.prank(initiator);
        vm.expectRevert(Compounder.InvalidInitiator.selector);
        compounder.compound(address(account), initiatorParams);
    }

    function testFuzz_Success_compound_NotNative(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounder), true);

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token0), users.accountOwner, initiatorParams.amount0, true);
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(token0);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            token0.approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
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
                poolKey.fee,
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

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));
    }

    function testFuzz_Success_compound_IsNative(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: uniV4 is allowed.
        deployUniswapV4AM();

        // And: Compounder is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounder), true);

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0.001 * 1e18, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Limited leftovers.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, type(uint8).max, 1e10));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, type(uint8).max, 1e10));

        // And: Account owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        vm.deal(users.accountOwner, initiatorParams.amount0);
        vm.prank(users.accountOwner);
        IWETH(address(weth9)).deposit{ value: initiatorParams.amount0 }();
        deal(address(token1), users.accountOwner, initiatorParams.amount1, true);
        {
            address[] memory assets_ = new address[](3);
            uint256[] memory assetIds_ = new uint256[](3);
            uint256[] memory assetAmounts_ = new uint256[](3);

            assets_[0] = address(positionManagerV4);
            assetIds_[0] = position.id;
            assetAmounts_[0] = 1;

            assets_[1] = address(weth9);
            assetAmounts_[1] = initiatorParams.amount0;

            assets_[2] = address(token1);
            assetAmounts_[2] = initiatorParams.amount1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), position.id);
            ERC20(address(weth9)).approve(address(account), initiatorParams.amount0);
            token1.approve(address(account), initiatorParams.amount1);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,) = stateView.getSlot0(poolKey.toId());
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
                poolKey.fee,
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

        // Then: New position should be deposited back into the account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));
    }
}
