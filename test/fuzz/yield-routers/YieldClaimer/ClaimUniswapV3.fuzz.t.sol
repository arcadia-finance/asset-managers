/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { UniswapV3Compounder_Fuzz_Test } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract Claim_UniswapV3_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test, UniswapV3Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(YieldClaimer_Fuzz_Test, UniswapV3Compounder_Fuzz_Test) {
        YieldClaimer_Fuzz_Test.setUp();

        // Deploy UniswapV3 fixtures.
        UniswapV3Compounder_Fuzz_Test.setUp();

        // And : YieldClaimer is deployed.
        deployYieldClaimer(
            address(0),
            address(0),
            address(0),
            address(0),
            address(nonfungiblePositionManager),
            address(0),
            address(0),
            MAX_INITIATOR_FEE_YIELD_CLAIMER
        );
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_claim_UniswapV3(TestVariables memory testVars, uint256 initiatorFee, address feeRecipient)
        public
    {
        // Given: feeRecipient is not the Account.
        vm.assume(feeRecipient != address(account));

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
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = uniV3AM.getFeeAmounts(tokenId);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(nonfungiblePositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);
        assertEq(token0.balanceOf(feeRecipient), totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_UniswapV3_NoFees(
        TestVariables memory testVars,
        uint256 initiatorFee,
        address feeRecipient
    ) public {
        // Given: feeRecipient is not the Account.
        vm.assume(feeRecipient != address(account));

        // And: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And : Valid pool state
        (testVars,) = givenValidBalancedState(testVars);

        testVars.feeAmount0 = 0;
        testVars.feeAmount1 = 0;

        // And : State is persisted
        uint256 tokenId = setState(testVars, usdStablePool);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = uniV3AM.getFeeAmounts(tokenId);
        assertEq(totalFee0, 0);
        assertEq(totalFee1, 0);

        // When : Calling collectFees()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(nonfungiblePositionManager), tokenId);

        // Then: No fees should have accrued.
        assertEq(token0.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token0.balanceOf(feeRecipient), 0);
        assertEq(token1.balanceOf(feeRecipient), 0);
    }

    function testFuzz_Success_claim_UniswapV3_recipientIsAccount(TestVariables memory testVars, uint256 initiatorFee)
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
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(nonfungiblePositionManager);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(nonfungiblePositionManager)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        (uint256 totalFee0, uint256 totalFee1) = uniV3AM.getFeeAmounts(tokenId);

        // When : Calling claimYield()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(nonfungiblePositionManager), tokenId);
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
        assertEq(assetAddresses[2], address(nonfungiblePositionManager));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
        assertEq(assetAmounts[1], totalFee1 - initiatorFee1);
    }
}
