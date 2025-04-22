/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { BitPackingLib } from "../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { ERC20 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import {
    PositionInfo,
    PositionInfoLibrary
} from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import { UniswapV4Compounder_Fuzz_Test } from "../../compounders/UniswapV4Compounder/_UniswapV4Compounder.fuzz.t.sol";
import { YieldClaimer_Fuzz_Test } from "./_YieldClaimer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claim" of contract "YieldClaimer".
 */
contract Claim_UniswapV4_YieldClaimer_Fuzz_Test is YieldClaimer_Fuzz_Test, UniswapV4Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(YieldClaimer_Fuzz_Test, UniswapV4Compounder_Fuzz_Test) {
        YieldClaimer_Fuzz_Test.setUp();

        // Deploy UniswapV4 fixtures.
        UniswapV4Compounder_Fuzz_Test.setUp();

        // And : YieldClaimer is deployed.
        deployYieldClaimer(
            address(0),
            address(0),
            address(0),
            address(0),
            address(0),
            address(positionManagerV4),
            address(weth9),
            MAX_INITIATOR_FEE_YIELD_CLAIMER
        );

        // Deploy Asset Module for native ETH.
        deployNativeAM();

        // Deploy native ETH pool.
        deployNativeEthPool();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_claim_UniswapV4(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
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

        // And: Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        testVars.liquidity = stateView.getLiquidity(stablePoolKey.toId());

        // And : Positive fee amounts
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Assume positive fees for both token0 and token1.
        uint256 totalFee0;
        uint256 totalFee1;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
            );
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (totalFee0, totalFee1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            vm.assume(totalFee0 > 0);
            vm.assume(totalFee1 > 0);
        }

        // When : Calling claim()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(positionManagerV4), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);
        assertEq(token0.balanceOf(feeRecipient), totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_UniswapV4_NoFees(
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

        // And: Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        testVars.liquidity = stateView.getLiquidity(stablePoolKey.toId());

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Assert that no fees have accrued.
        uint256 totalFee0;
        uint256 totalFee1;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
            );
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (totalFee0, totalFee1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            assertEq(totalFee0, 0);
            assertEq(totalFee1, 0);
        }

        // When : Calling claim()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(positionManagerV4), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        assertEq(token0.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), 0);
        assertEq(token0.balanceOf(feeRecipient), 0);
        assertEq(token1.balanceOf(feeRecipient), 0);
    }

    function testFuzz_Success_claim_UniswapV4_nativeETH(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
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

        // And: Valid state
        (testVars,) = givenValidBalancedState(testVars, nativeEthPoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, nativeEthPoolKey);

        testVars.liquidity = stateView.getLiquidity(nativeEthPoolKey.toId());

        // And : Positive fee amounts
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, nativeEthPoolKey, testVars.liquidity);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Assume positive fees for both token0 and token1.
        uint256 totalFee0;
        uint256 totalFee1;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
            );
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
            (totalFee0, totalFee1) = getFeeAmounts(tokenId, nativeEthPoolKey.toId(), info, liquidity);
            vm.assume(totalFee0 > 0);
            vm.assume(totalFee1 > 0);
        }

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.prank(registry.owner());
            erc20AM.addAsset(address(weth9), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // When : Calling claim()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(positionManagerV4), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(ERC20(address(weth9)).balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);
        assertEq(ERC20(address(weth9)).balanceOf(feeRecipient), totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_UniswapV4_RecipientIsAccount(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
        uint256 initiatorFee
    ) public {
        // Given: Set account info, fee recipient is the Account itself.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And: Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        testVars.liquidity = stateView.getLiquidity(stablePoolKey.toId());

        // And : Positive fee amounts
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, stablePoolKey, testVars.liquidity);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Assume positive fees for both token0 and token1.
        uint256 totalFee0;
        uint256 totalFee1;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
            );
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (totalFee0, totalFee1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            vm.assume(totalFee0 > 0);
            vm.assume(totalFee1 > 0);
        }

        // When : Calling claim()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(positionManagerV4), tokenId);

        // Then: Fees should have accrued in Account.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(token0));
        assertEq(assetAddresses[1], address(token1));
        assertEq(assetAddresses[2], address(positionManagerV4));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
        assertEq(assetAmounts[1], totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_claim_UniswapV4_nativeETH_RecipientIsAccount(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
        uint256 initiatorFee
    ) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        yieldClaimer.setAccountInfo(address(account), initiatorYieldClaimer, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_FEE_YIELD_CLAIMER, INITIATOR_FEE_YIELD_CLAIMER);
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.setInitiatorFee(initiatorFee);

        // And: Valid state
        (testVars,) = givenValidBalancedState(testVars, nativeEthPoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, nativeEthPoolKey);

        testVars.liquidity = stateView.getLiquidity(nativeEthPoolKey.toId());

        // And : Positive fee amounts
        feeData.desiredFee0 = bound(feeData.desiredFee0, 1, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 1, type(uint16).max);
        feeData = setFeeState(feeData, nativeEthPoolKey, testVars.liquidity);

        // And : Transfer position to account owner
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, tokenId);

        {
            address[] memory assets_ = new address[](1);
            assets_[0] = address(positionManagerV4);
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = tokenId;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            ERC721(address(positionManagerV4)).approve(address(account), tokenId);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And : Assume positive fees for both token0 and token1.
        uint256 totalFee0;
        uint256 totalFee1;
        {
            bytes32 positionId = keccak256(
                abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
            );
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
            (totalFee0, totalFee1) = getFeeAmounts(tokenId, nativeEthPoolKey.toId(), info, liquidity);
            vm.assume(totalFee0 > 0);
            vm.assume(totalFee1 > 0);
        }

        // And: Add WETH to Registry.
        {
            ethOracle = initMockedOracle(8, "ETH / USD", uint256(1e8));
            uint80[] memory oracleEthToUsdArr = new uint80[](1);

            vm.prank(registry.owner());
            erc20AM.addAsset(address(weth9), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
        }

        // When : Calling claim()
        vm.prank(initiatorYieldClaimer);
        yieldClaimer.claim(address(account), address(positionManagerV4), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(ERC20(address(weth9)).balanceOf(initiatorYieldClaimer), initiatorFee0);
        assertEq(token1.balanceOf(initiatorYieldClaimer), initiatorFee1);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(weth9));
        assertEq(assetAddresses[1], address(token1));
        assertEq(assetAddresses[2], address(positionManagerV4));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
        assertEq(assetAmounts[1], totalFee1 - initiatorFee1);
    }
}
