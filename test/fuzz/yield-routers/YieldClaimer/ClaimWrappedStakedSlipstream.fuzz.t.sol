/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { AccountSpot } from "../../../../lib/accounts-v2/src/accounts/AccountSpot.sol";
import { ArcadiaAccountsFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/ArcadiaAccountsFixture.f.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { FullMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FullMath.sol";
import { Fuzz_Test } from "../../../../lib/accounts-v2/test/fuzz/Fuzz.t.sol";
import { StakedSlipstreamAM } from "../../../../lib/accounts-v2/src/asset-modules/Slipstream/StakedSlipstreamAM.sol";
import { StakedSlipstreamAM_Fuzz_Test } from
    "../../../../lib/accounts-v2/test/fuzz/asset-modules/StakedSlipstreamAM/_StakedSlipstreamAM.fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { WrappedStakedSlipstreamFixture } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/WrappedStakedSlipstream.f.sol";
import { YieldClaimer } from "../../../../src/yield-routers/YieldClaimer.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract ClaimWrappedStakedSlipstream_YieldClaimer_Fuzz_Test is
    YieldClaimer_Fuzz_Test,
    StakedSlipstreamAM_Fuzz_Test,
    WrappedStakedSlipstreamFixture
{
    using FixedPointMathLib for uint256;
    using stdStorage for StdStorage;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp()
        public
        virtual
        override(YieldClaimer_Fuzz_Test, StakedSlipstreamAM_Fuzz_Test, WrappedStakedSlipstreamFixture)
    {
        YieldClaimer_Fuzz_Test.setUp();

        // Deploy Slipstream fixtures.
        StakedSlipstreamAM_Fuzz_Test.setUp();
        deployStakedSlipstreamAM();

        // Given : Deploy WrappedStakedSlipstream fixture.
        WrappedStakedSlipstreamFixture.setUp();

        // And : Account is a Spot Account.
        deploySpotAccount();

        // And : YieldClaimer is deployed.
        deployYieldClaimer(
            address(AERO),
            address(0),
            address(0),
            address(wrappedStakedSlipstream),
            address(0),
            address(0),
            address(0),
            MAX_INITIATOR_FEE
        );
    }

    function addAssetToArcadia(address asset, int256 price) internal override(Fuzz_Test, ArcadiaAccountsFixture) {
        super.addAssetToArcadia(asset, price);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_claim_WrappedStakedSlipstream_RecipientIsAccount(
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
        slipstreamPositionManager.approve(address(wrappedStakedSlipstream), assetId);
        wrappedStakedSlipstream.mint(assetId);
        vm.stopPrank();

        // And : Deposit position in Account
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), assetId);

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

        // And : Set the initiator and recipient for the account.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiator, address(account));

        // When : An initiator claims pending Aero from staked slipstream position in Account.
        vm.startPrank(initiator);
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(wrappedStakedSlipstream), assetId);
        yieldClaimer.claim(address(account), address(wrappedStakedSlipstream), assetId);
        vm.stopPrank();

        // Then : Account should still own the position.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(assetId), address(account));
        // And : The initiator should have received its share
        uint256 expectedInitiatorShare = rewardsExpected.mulDivDown(INITIATOR_FEE, 1e18);
        assertEq(ERC20(AERO).balanceOf(initiator), expectedInitiatorShare);
        // And : Account should have received AERO.
        uint256 expectedAccountBalance = rewardsExpected - expectedInitiatorShare;
        assertEq(ERC20(AERO).balanceOf(address(account)), expectedAccountBalance);
        // And : Account should be set to the zero address.
        assertEq(yieldClaimer.getAccount(), address(0));
    }

    function testFuzz_Success_claim_WrappedStakedSlipstream_RecipientIsNotAccount(
        StakedSlipstreamAM.PositionState memory position,
        uint256 rewardGrowthGlobalX128Last,
        uint256 rewardGrowthGlobalX128Current,
        int24 tick,
        address recipient
    ) public {
        // Given: Recipient is not account or address(0).
        vm.assume(recipient != address(account));
        vm.assume(recipient != address(0));

        // And: a valid position.
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

        // And : Deposit position in Account
        vm.prank(users.liquidityProvider);
        ERC721(address(wrappedStakedSlipstream)).transferFrom(users.liquidityProvider, address(account), assetId);

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

        // And : Set the initiator and recipient for the account.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiator, recipient);

        // When : An initiator claims pending Aero from staked slipstream position in Account.
        vm.startPrank(initiator);
        vm.expectEmit();
        emit YieldClaimer.Claimed(address(account), address(wrappedStakedSlipstream), assetId);
        yieldClaimer.claim(address(account), address(wrappedStakedSlipstream), assetId);
        vm.stopPrank();

        // Then : Account should still own the position.
        assertEq(ERC721(address(wrappedStakedSlipstream)).ownerOf(assetId), address(account));
        // And : The initiator should have received its share
        uint256 expectedInitiatorShare = rewardsExpected.mulDivDown(INITIATOR_FEE, 1e18);
        assertEq(ERC20(AERO).balanceOf(initiator), expectedInitiatorShare);
        // And : Account should not have received AERO.
        assertEq(ERC20(AERO).balanceOf(address(account)), 0);
        // And: Recipient should have received AERO.
        uint256 expectedAccountBalance = rewardsExpected - expectedInitiatorShare;
        assertEq(ERC20(AERO).balanceOf(recipient), expectedAccountBalance);
        // And : Account should be set to the zero address.
        assertEq(yieldClaimer.getAccount(), address(0));
    }
}
