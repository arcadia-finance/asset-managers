/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { SlipstreamCompounder_Fuzz_Test } from "../../compounders/SlipstreamCompounder/_SlipstreamCompounder.fuzz.t.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract Claim_Slipstream_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test, SlipstreamCompounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(YieldClaimer_Fuzz_Test, SlipstreamCompounder_Fuzz_Test) {
        YieldClaimer_Fuzz_Test.setUp();

        // Deploy Slisptream fixtures.
        SlipstreamCompounder_Fuzz_Test.setUp();

        // And : YieldClaimer is deployed.
        deployYieldClaimer(
            address(0),
            address(slipstreamPositionManager),
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            MAX_INITIATOR_FEE_YIELD_CLAIMER
        );
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_claim_Slipstream(
        TestVariables memory testVars,
        uint256 initiatorFee,
        address feeRecipient
    ) public {
        // Given: feeRecipient is not the Account or address(0).
        vm.assume(feeRecipient != address(account));
        vm.assume(feeRecipient != address(0));
        vm.assume(feeRecipient != address(yieldClaimer));

        // And: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);

        uint256 initialBalance0 = token0.balanceOf(feeRecipient);
        uint256 initialBalance1 = token1.balanceOf(feeRecipient);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);
        assertEq(token0.balanceOf(feeRecipient), initialBalance0 + totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), initialBalance1 + totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_Slipstream_Token0Only(
        TestVariables memory testVars,
        uint256 initiatorFee,
        address feeRecipient
    ) public {
        // Given: feeRecipient is not the Account or address(0).
        vm.assume(feeRecipient != address(account));
        vm.assume(feeRecipient != address(0));
        vm.assume(feeRecipient != address(yieldClaimer));

        // And: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: Fees should only have accrued in token0.
        testVars.feeAmount1 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee1, 0);

        uint256 initialBalance0 = token0.balanceOf(feeRecipient);
        uint256 initialBalance1 = token1.balanceOf(feeRecipient);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token0.balanceOf(feeRecipient), initialBalance0 + totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), initialBalance1);
    }

    function testFuzz_Success_claim_Slipstream_Token1Only(
        TestVariables memory testVars,
        uint256 initiatorFee,
        address feeRecipient
    ) public {
        // Given: feeRecipient is not the Account or address(0).
        vm.assume(feeRecipient != address(account));
        vm.assume(feeRecipient != address(0));
        vm.assume(feeRecipient != address(yieldClaimer));

        // And: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: Fees should only have accrued in token1.
        testVars.feeAmount0 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee0, 0);

        uint256 initialBalance0 = token0.balanceOf(feeRecipient);
        uint256 initialBalance1 = token1.balanceOf(feeRecipient);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);
        assertEq(token0.balanceOf(feeRecipient), initialBalance0);
        assertEq(token1.balanceOf(feeRecipient), initialBalance1 + totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_Slipstream_NoFees(
        TestVariables memory testVars,
        uint256 initiatorFee,
        address feeRecipient
    ) public {
        // Given: feeRecipient is not the Account or address(0).
        vm.assume(feeRecipient != address(account));
        vm.assume(feeRecipient != address(0));
        vm.assume(feeRecipient != address(yieldClaimer));

        // And: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: No fees have accrued.
        testVars.feeAmount0 = 0;
        testVars.feeAmount1 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee0, 0);
        assertEq(totalFee1, 0);

        uint256 initialBalance0 = token0.balanceOf(feeRecipient);
        uint256 initialBalance1 = token1.balanceOf(feeRecipient);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: No fees should have accrued.
        assertEq(token0.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token0.balanceOf(feeRecipient), initialBalance0);
        assertEq(token1.balanceOf(feeRecipient), initialBalance1);
    }

    function testFuzz_Success_claim_Slipstream_recipientIsAccount(TestVariables memory testVars, uint256 initiatorFee)
        public
    {
        // Given: Set account info, the account is set as fee recipient.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state
        (testVars,) = givenValidBalancedState(testVars);

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);

        // When : Calling claimYield()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);
        vm.assume(totalFee0 > 0);
        vm.assume(totalFee1 > 0);

        // Then: Fees should have accrued in Account.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(token0));
        assertEq(assetAddresses[1], address(token1));
        assertEq(assetAddresses[2], address(slipstreamPositionManager));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
        assertEq(assetAmounts[1], totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_Slipstream_Token0Only_RecipientIsAccount(
        TestVariables memory testVars,
        uint256 initiatorFee
    ) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: Fees should only have accrued in token0.
        testVars.feeAmount1 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee1, 0);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(token0));
        assertEq(assetAddresses[1], address(slipstreamPositionManager));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
    }

    function testFuzz_Success_claim_Slipstream_NoFees_RecipientIsAccount(
        TestVariables memory testVars,
        uint256 initiatorFee
    ) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: Fees should only have accrued in token1.
        testVars.feeAmount0 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee0, 0);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(token1));
        assertEq(assetAddresses[1], address(slipstreamPositionManager));
        assertEq(assetAmounts[0], totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_Slipstream_Token1Only_RecipientIsAccount(
        TestVariables memory testVars,
        uint256 initiatorFee
    ) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state.
        (testVars,) = givenValidBalancedState(testVars);
        // And: No fees have accrued.
        testVars.feeAmount0 = 0;
        testVars.feeAmount1 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(slipstreamPositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(slipstreamPositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(slipstreamPositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = slipstreamAM.getFeeAmounts(tokenId);
        assertEq(totalFee0, 0);
        assertEq(totalFee1, 0);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(slipstreamPositionManager), tokenId);

        // Then: No fees should have accrued.
        assertEq(token0.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token0.balanceOf(address(account)), 0);
        assertEq(token1.balanceOf(address(account)), 0);
    }
}
