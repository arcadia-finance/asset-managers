/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounder_Fuzz_Test } from "./_SlipstreamCompounder.fuzz.t.sol";

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { ICLPoolExtension } from
    "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/extensions/interfaces/ICLPoolExtension.sol";
import { ICLSwapRouter } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/interfaces/ICLSwapRouter.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";

/**
 * @notice Fuzz tests for the function "compoundFees" of contract "SlipstreamCompounder".
 */
contract CompoundFees_SlipstreamCompounder_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        SlipstreamCompounder_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compoundFees_Reentered(address random, uint256 tokenId, uint160 sqrtPrice) public {
        // Given: A rebalance is ongoing.
        vm.assume(random != address(0));
        compounder.setAccount(random);

        // When: Calling compoundFees().
        // Then: It should revert.
        vm.expectRevert(SlipstreamCompounder.Reentered.selector);
        compounder.compoundFees(address(account), tokenId, sqrtPrice);
    }

    function testFuzz_Revert_compoundFees_InitiatorNotValid(address notInitiator, uint256 tokenId, uint160 sqrtPrice)
        public
    {
        // Given: The caller is not the initiator.
        vm.assume(initiator != notInitiator);

        // When: Calling compoundFees().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(SlipstreamCompounder.InitiatorNotValid.selector);
        compounder.compoundFees(address(account), tokenId, sqrtPrice);
    }

    function testFuzz_Success_compoundFees(TestVariables memory testVars) public {
        // And : Valid state
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

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);

        (uint160 sqrtPrice,,,,,) = usdStablePool.slot0();

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, uint256(sqrtPrice));

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = testVars.feeAmount0 * 10 ** token0.decimals();
        uint256 totalFee1 = testVars.feeAmount1 * 10 ** token1.decimals();

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        initiatorFeeToken0Calculated = initiatorFeeToken0Calculated;
        initiatorFeeToken1Calculated = initiatorFeeToken1Calculated;
        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }

    function testFuzz_Success_compoundFees_MoveTickRight(TestVariables memory testVars) public {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(usdStablePool));

        // And : Valid state
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

        // And : Move tick right
        uint256 amount1ToSwap;
        {
            // Swap max amount to move ticks right (ensure tolerance is not exceeded when compounding afterwards)
            amount1ToSwap = 100_000_000_000_000 * 10 ** token1.decimals();

            deal(address(token1), users.liquidityProvider, amount1ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token1.approve(address(clSwapRouter), amount1ToSwap);

            ICLSwapRouter.ExactInputSingleParams memory exactInputParams = ICLSwapRouter.ExactInputSingleParams({
                tokenIn: address(token1),
                tokenOut: address(token0),
                tickSpacing: TICK_SPACING,
                recipient: users.liquidityProvider,
                deadline: block.timestamp,
                amountIn: amount1ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            clSwapRouter.exactInputSingle(exactInputParams);

            vm.stopPrank();
        }

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);

        (uint160 sqrtPrice,,,,,) = usdStablePool.slot0();

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, uint256(sqrtPrice));

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : Initiator fees should have been distributed
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = testVars.feeAmount0 * 10 ** token0.decimals();
        uint256 totalFee1 = testVars.feeAmount1 * 10 ** token1.decimals() + amount1ToSwap * POOL_FEE / 1e6;

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);

        uint256 initiatorFeeUsdValue;
        uint256 totalFeeInUsdValue;
        if (token0.decimals() < token1.decimals()) {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e30 / 1e18 + initiatorFeesToken1 * 1e18 / 1e18;

            totalFeeInUsdValue = totalFee0 * 1e30 / 1e18 + totalFee1 * 1e18 / 1e18;
        } else {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e18 / 1e18 + initiatorFeesToken1 * 1e30 / 1e18;

            totalFeeInUsdValue = totalFee0 * 1e18 / 1e18 + totalFee1 * 1e30 / 1e18;
        }
        // Ensure USD value of initiator fees is max INITIATOR_SHARE from total fees.
        assertLe(initiatorFeeUsdValue, totalFeeInUsdValue * INITIATOR_SHARE / 1e18);
    }

    function testFuzz_Success_compoundFees_MoveTickLeft(TestVariables memory testVars) public {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(usdStablePool));

        // And : Valid state
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

        // And : Move tick left.
        uint256 amount0ToSwap;
        {
            // Swap max amount to move ticks left (ensure tolerance is not exceeded when compounding afterwards)
            amount0ToSwap = 100_000_000_000_000 * 10 ** token0.decimals();

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token0.approve(address(clSwapRouter), amount0ToSwap);

            ICLSwapRouter.ExactInputSingleParams memory exactInputParams = ICLSwapRouter.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                tickSpacing: TICK_SPACING,
                recipient: users.liquidityProvider,
                deadline: block.timestamp,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            clSwapRouter.exactInputSingle(exactInputParams);

            vm.stopPrank();
        }

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);

        (uint160 sqrtPrice,,,,,) = usdStablePool.slot0();

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, uint256(sqrtPrice));

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = slipstreamPositionManager.positions(tokenId);
        assertGt(newLiquidity, initialLiquidity);

        // And : Initiator fees should have been distributed
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 totalFee0 = testVars.feeAmount0 * 10 ** token0.decimals() + amount0ToSwap * POOL_FEE / 1e6;
        uint256 totalFee1 = testVars.feeAmount1 * 10 ** token1.decimals();

        uint256 initiatorFeeToken0Calculated = totalFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = totalFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);

        uint256 initiatorFeeUsdValue;
        uint256 totalFeeInUsdValue;
        if (token0.decimals() < token1.decimals()) {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e30 / 1e18 + initiatorFeesToken1 * 1e18 / 1e18;

            totalFeeInUsdValue = totalFee0 * 1e30 / 1e18 + totalFee1 * 1e18 / 1e18;
        } else {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e18 / 1e18 + initiatorFeesToken1 * 1e30 / 1e18;

            totalFeeInUsdValue = totalFee0 * 1e18 / 1e18 + totalFee1 * 1e30 / 1e18;
        }
        // Ensure USD value of initiator fees is max INITIATOR_SHARE from total fees.
        assertLe(initiatorFeeUsdValue, totalFeeInUsdValue * INITIATOR_SHARE / 1e18);
    }
}
