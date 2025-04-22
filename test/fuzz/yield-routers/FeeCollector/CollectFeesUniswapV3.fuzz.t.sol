/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FeeCollector } from "./_FeeCollector.fuzz.t.sol";
import { FeeCollectorExtension } from "../../../utils/extensions/FeeCollectorExtension.sol";
import { FeeCollector_Fuzz_Test } from "./_FeeCollector.fuzz.t.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { ISwapRouter02 } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";
import { IUniswapV3PoolExtension } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";
import { UniswapV3Compounder_Fuzz_Test } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";
import { UniswapV4Logic } from "../../../../src/yield-routers/libraries/UniswapV4Logic.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Fuzz tests for the function "collectFees" of contract "FeeCollector".
 */
contract CollectFees_FeeCollector_Fuzz_Test is UniswapV3Compounder_Fuzz_Test, FeeCollector_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV3Compounder_Fuzz_Test, FeeCollector_Fuzz_Test) {
        UniswapV3Compounder_Fuzz_Test.setUp();

        // Given : Fee Collector is deployed.
        deployFeeCollector();

        // And : FeeCollector is allowed as Asset Manager.
        vm.prank(users.accountOwner);
        account.setAssetManager(address(feeCollector), true);

        // And : Create and set initiator details.
        initiator = createUser("initiator");
        feeRecipient = createUser("feeRecipient");
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_collectFees_Reentered(address random, uint256 tokenId) public {
        // Given: An account address is defined in storage.
        vm.assume(random != address(0));
        feeCollector.setAccount(random);

        // When: Calling collectFees().
        // Then: It should revert.
        vm.expectRevert(FeeCollector.Reentered.selector);
        feeCollector.collectFees(address(account), address(nonfungiblePositionManager), tokenId);
    }

    function testFuzz_Revert_collectFees_InvalidInitiator(address notInitiator, uint256 tokenId) public {
        // Given: The caller is not the initiator.
        vm.assume(initiator != notInitiator);

        // When: Calling collectFees().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(FeeCollector.InvalidInitiator.selector);
        feeCollector.collectFees(address(account), address(nonfungiblePositionManager), tokenId);
    }

    function testFuzz_Revert_collectFees_InvalidPositionManager(address random, uint256 tokenId) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        feeCollector.setAccountInfo(address(account), initiator, feeRecipient);

        // And: The positionManager is not a valid one.
        vm.assume(random != address(nonfungiblePositionManager));

        // When: Calling collectFees().
        // Then: It should revert.
        vm.prank(initiator);
        vm.expectRevert(FeeCollector.InvalidPositionManager.selector);
        feeCollector.collectFees(address(account), random, tokenId);
    }

    function testFuzz_Success_collectFees(TestVariables memory testVars, uint256 initiatorFee) public {
        // Given: Set account info.
        vm.prank(users.accountOwner);
        feeCollector.setAccountInfo(address(account), initiator, feeRecipient);

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_SHARE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        feeCollector.setInitiatorFee(initiatorFee);

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
        vm.prank(initiator);
        feeCollector.collectFees(address(account), address(nonfungiblePositionManager), tokenId);

        // Then: Fees should have been sent to recipient.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiator), initiatorFee0);
        assertEq(token1.balanceOf(initiator), initiatorFee1);
        assertEq(token0.balanceOf(feeRecipient), totalFee0 - initiatorFee0);
        assertEq(token1.balanceOf(feeRecipient), totalFee1 - initiatorFee1);
    }

    function testFuzz_Success_collectFees_recipientIsAccount(TestVariables memory testVars, uint256 initiatorFee)
        public
    {
        // Given: Set account info, the account is set as fee recipient.
        vm.prank(users.accountOwner);
        feeCollector.setAccountInfo(address(account), initiator, address(account));

        // And: Set initiator fee.
        initiatorFee = bound(initiatorFee, MIN_INITIATOR_SHARE, MAX_INITIATOR_FEE);
        vm.prank(initiator);
        feeCollector.setInitiatorFee(initiatorFee);

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
        vm.prank(initiator);
        feeCollector.collectFees(address(account), address(nonfungiblePositionManager), tokenId);
        vm.assume(totalFee0 > 0);
        vm.assume(totalFee1 > 0);

        // Then: Fees should have accrued in Account.
        // And: The initiator should have received its fee.
        uint256 initiatorFee0 = totalFee0.mulDivDown(initiatorFee, 1e18);
        uint256 initiatorFee1 = totalFee1.mulDivDown(initiatorFee, 1e18);

        assertEq(token0.balanceOf(initiator), initiatorFee0);
        assertEq(token1.balanceOf(initiator), initiatorFee1);

        (address[] memory assetAddresses,, uint256[] memory assetAmounts) = account.generateAssetData();
        assertEq(assetAddresses[0], address(token0));
        assertEq(assetAddresses[1], address(token1));
        assertEq(assetAddresses[2], address(nonfungiblePositionManager));
        assertEq(assetAmounts[0], totalFee0 - initiatorFee0);
        assertEq(assetAmounts[1], totalFee1 - initiatorFee1);
    }

    /*////////////////////////////////////////////////////////////////
                            HELPERS
    /////////////////////////////////////////////////////////////// */

    function deployFeeCollector() internal {
        feeCollector = new FeeCollectorExtension(MAX_INITIATOR_FEE);

        // Overwrite addresses stored as constant in FeeCollector.
        bytes memory bytecode = address(feeCollector).code;

        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1),
            abi.encodePacked(nonfungiblePositionManager),
            false
        );

        // Overwrite Arcadia contract addresses, stored as constants in Rebalancer.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );

        vm.etch(address(feeCollector), bytecode);
    }
}
