/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { AccountSpot } from "../../../../lib/accounts-v2/src/accounts/AccountSpot.sol";
import { AeroClaimer } from "../../../../src/yield-routers/AeroClaimer.sol";
import { AeroClaimer_Fuzz_Test } from "./_AeroClaimer.fuzz.t.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { WrappedStakedSlipstreamFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/WrappedStakedSlipstream.f.sol";

/**
 * @notice Fuzz tests for the function "claimAero" of contract "AeroClaimer".
 */
contract ClaimAero_AeroClaimer_Fuzz_Test is AeroClaimer_Fuzz_Test, WrappedStakedSlipstreamFixture {
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(AeroClaimer_Fuzz_Test, WrappedStakedSlipstreamFixture) {
        AeroClaimer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_claimAero_Reentered(address positionmanager, address random, uint256 tokenId) public {
        // Given: Account is not address(0).
        vm.assume(random != address(0));

        // And: An account address is defined in storage.
        aeroClaimer.setAccount(random);

        // When: Calling claimAero().
        // Then: It should revert.
        vm.expectRevert(AeroClaimer.Reentered.selector);
        aeroClaimer.claimAero(address(account), positionmanager, tokenId);
    }

    function testFuzz_Revert_claimAero_InvalidInitiator(address positionmanager, address notInitiator, uint256 tokenId)
        public
    {
        // Given: The caller is not the initiator.
        vm.assume(initiator != notInitiator);

        // When: Calling claimAero().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(AeroClaimer.InvalidInitiator.selector);
        aeroClaimer.claimAero(address(account), positionmanager, tokenId);
    }

    function testFuzz_Revert_claimAero_InvalidPositionManager(address positionmanager, uint256 tokenId) public {
        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And: The positionmanager is not a staked slipstream position manager.
        vm.assume(positionmanager != address(stakedSlipstreamAM));
        vm.assume(positionmanager != address(wrappedStakedSlipstream));

        // When: Calling claimAero().
        // Then: It should revert.
        vm.prank(initiator);
        vm.expectRevert(AeroClaimer.InvalidPositionManager.selector);
        aeroClaimer.claimAero(address(account), positionmanager, tokenId);
    }

    function testFuzz_Success_claimAero_StakedSlipstreamAM(
        StakedSlipstreamAM.PositionState memory position,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        int24 tick
    ) public {
        // Given : a valid position.
        position = givenValidPosition(position, 1);

        // And : the current tick of the pool is in range (can't be equal to tickUpper, but can be equal to tickLower).
        tick = int24(bound(tick, position.tickLower, position.tickUpper - 1));
        deployAndAddGauge(tick);

        // Given : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // And : assetId is minted.
        uint256 assetId = addLiquidity(position);

        // And: Position is staked.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(stakedSlipstreamAM), assetId);
        stakedSlipstreamAM.mint(assetId);
        vm.stopPrank();

        // And: Transfer the position to the Account owner and deposit in Account
        {
            vm.prank(users.liquidityProvider);
            stakedSlipstreamAM.transferFrom(users.liquidityProvider, users.accountOwner, assetId);

            address[] memory assets_ = new address[](1);
            assets_[0] = address(stakedSlipstreamAM);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = assetId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(stakedSlipstreamAM)).approve(address(account), assetId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Rewards are earned.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // And : Rewards amount is not zero.
        uint256 rewardGrowthInsideX128;
        unchecked {
            rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
        }
        uint256 liquidity = getActualLiquidity(position);
        uint256 rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, liquidity, FixedPoint128.Q128);
        // Expect minimum rewards to not have 0 initiator fee.
        vm.assume(rewardsExpected > 1e4);
        // Avoid overflow in amountClaimed * fee, rewards would be irrealistically high.
        vm.assume(rewardsExpected < type(uint128).max);

        // When : An initiator claims pending Aero from staked slipstream position in Account.
        vm.startPrank(initiator);
        vm.expectEmit();
        emit AeroClaimer.AeroClaimed(address(account), address(stakedSlipstreamAM), assetId);
        aeroClaimer.claimAero(address(account), address(stakedSlipstreamAM), assetId);
        vm.stopPrank();

        // Then : Account should still own the position.
        assertEq(ERC721(address(stakedSlipstreamAM)).ownerOf(assetId), address(account));
        // And : Account should have received AERO.
        uint256 expectedInitiatorShare = rewardsExpected.mulDivDown(INITIATOR_SHARE, 1e18);
        uint256 expectedAccountBalance = rewardsExpected - expectedInitiatorShare;
        assertEq(ERC20(AERO).balanceOf(initiator), expectedInitiatorShare);
        assertGt(ERC20(AERO).balanceOf(initiator), 0);
        // And : The initiator should have received its share
        assertEq(ERC20(AERO).balanceOf(address(account)), expectedAccountBalance);
        assertGt(ERC20(AERO).balanceOf(address(account)), 0);
        // And : Account should be set to the zero address.
        assertEq(aeroClaimer.getAccount(), address(0));
    }

    function testFuzz_Success_claimAero_WrappedStakedSlipstream(
        StakedSlipstreamAM.PositionState memory position,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        int24 tick
    ) public {
        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And: Account is a Spot Account.
        vm.prank(users.accountOwner);
        account = AccountV1(address(new AccountSpot(address(factory))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));

        // And : Set the initiator for the account.
        vm.startPrank(users.accountOwner);
        account.setAssetManager(address(aeroClaimer), true);
        aeroClaimer.setInitiator(address(account), initiator);
        vm.stopPrank();

        // And : a valid position.
        position = givenValidPosition(position, 1);

        // And : the current tick of the pool is in range (can't be equal to tickUpper, but can be equal to tickLower).
        tick = int24(bound(tick, position.tickLower, position.tickUpper - 1));
        deployAndAddGauge(tick);

        // Given : An initial rewardGrowthGlobalX128.
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Last
        );

        // And : assetId is minted.
        uint256 assetId = addLiquidity(position);

        // And: Position is staked.
        vm.startPrank(users.liquidityProvider);
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), assetId);
        wrappedStakedSlipstream.mint(assetId);
        vm.stopPrank();

        // And: Transfer the position to the Account owner and deposit in Account
        {
            vm.prank(users.liquidityProvider);
            wrappedStakedSlipstream.transferFrom(users.liquidityProvider, users.accountOwner, assetId);

            address[] memory assets_ = new address[](1);
            assets_[0] = address(wrappedStakedSlipstream);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = assetId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.prank(users.accountOwner);
            ERC721(address(wrappedStakedSlipstream)).transferFrom(users.accountOwner, address(account), assetId);
        }

        // And : Rewards are earned.
        vm.warp(block.timestamp + 1);
        deal(AERO, address(gauge), type(uint256).max, true);
        stdstore.target(address(pool)).sig(pool.rewardReserve.selector).checked_write(type(uint256).max);
        stdstore.target(address(pool)).sig(pool.rewardGrowthGlobalX128.selector).checked_write(
            rewardGrowthGlobalX128Current
        );

        // And : Rewards amount is not zero.
        uint256 rewardGrowthInsideX128;
        unchecked {
            rewardGrowthInsideX128 = rewardGrowthGlobalX128Current - rewardGrowthGlobalX128Last;
        }
        uint256 liquidity = getActualLiquidity(position);
        uint256 rewardsExpected = FullMath.mulDiv(rewardGrowthInsideX128, liquidity, FixedPoint128.Q128);
        // Expect minimum rewards to not have 0 initiator fee.
        vm.assume(rewardsExpected > 1e4);
        // Avoid overflow in amountClaimed * fee, rewards would be irrealistically high.
        vm.assume(rewardsExpected < type(uint128).max);

        // When : An initiator claims pending Aero from staked slipstream position in Account.
        vm.startPrank(initiator);
        vm.expectEmit();
        emit AeroClaimer.AeroClaimed(address(account), address(wrappedStakedSlipstream), assetId);
        aeroClaimer.claimAero(address(account), address(wrappedStakedSlipstream), assetId);
        vm.stopPrank();

        // Then : Account should still own the position.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(assetId), address(account));
        // And : Account should have received AERO.
        uint256 expectedInitiatorShare = rewardsExpected.mulDivDown(INITIATOR_SHARE, 1e18);
        uint256 expectedAccountBalance = rewardsExpected - expectedInitiatorShare;
        assertEq(ERC20(AERO).balanceOf(initiator), expectedInitiatorShare);
        assertGt(ERC20(AERO).balanceOf(initiator), 0);
        // And : The initiator should have received its share
        assertEq(ERC20(AERO).balanceOf(address(account)), expectedAccountBalance);
        assertGt(ERC20(AERO).balanceOf(address(account)), 0);
        // And : Account should be set to the zero address.
        assertEq(aeroClaimer.getAccount(), address(0));
    }
}
