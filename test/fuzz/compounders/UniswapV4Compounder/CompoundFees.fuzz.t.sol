/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "compoundFees" of contract "UniswapV4Compounder".
 */
contract CompoundFees_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        UniswapV4Compounder_Fuzz_Test.setUp();

        deployNativeAM();
        deployNativeEthPool();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_compoundFees_FeeAmountTooLow(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
        address initiator
    ) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // And : Fee amounts are too low (in $)
        feeData.desiredFee0 = ((COMPOUND_THRESHOLD / 1e18) / 2) - 1;
        feeData.desiredFee1 = (COMPOUND_THRESHOLD / 1e18) / 2;
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

        // When : Calling compoundFees().
        vm.startPrank(initiator);
        vm.expectRevert(UniswapV4Compounder.BelowThreshold.selector);
        compounder.compoundFees(address(account), tokenId);
        vm.stopPrank();
    }

    function testFuzz_Success_compoundFees(TestVariables memory testVars, FeeGrowth memory feeData, address initiator)
        public
    {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);

        // And : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // And : Fee amounts above minimum treshold.
        feeData.desiredFee0 = bound(feeData.desiredFee0, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
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

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );
        uint256 newLiquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
        assertGt(newLiquidity, testVars.liquidity);

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 initiatorFeeToken0Calculated = feeData.desiredFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = feeData.desiredFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }

    function testFuzz_Success_compoundFees_MoveTickRight(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
        address initiator
    ) public {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);

        // And : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // And : Fee amounts above minimum treshold.
        feeData.desiredFee0 = bound(feeData.desiredFee0, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
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

        // And : Move tick right.
        {
            (, int24 currentTick,,) = stateView.getSlot0(stablePoolKey.toId());
            int256 tickDelta = (int256(testVars.tickUpper - currentTick) * 9500) / 10_000;
            int24 newTick = currentTick + int24(tickDelta);
            poolManager.setCurrentPrice(stablePoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));
        }

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );
        uint256 newLiquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
        assertGt(newLiquidity, testVars.liquidity);

        // And : Initiator fees should have been distributed
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 initiatorFeeToken0Calculated = feeData.desiredFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = feeData.desiredFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);

        uint256 initiatorFeeUsdValue;
        uint256 totalFeeInUsdValue;
        if (token0.decimals() < token1.decimals()) {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e30 / 1e18 + initiatorFeesToken1 * 1e18 / 1e18;

            totalFeeInUsdValue = feeData.desiredFee0 * 1e30 / 1e18 + feeData.desiredFee1 * 1e18 / 1e18;
        } else {
            initiatorFeeUsdValue = initiatorFeesToken0 * 1e18 / 1e18 + initiatorFeesToken1 * 1e30 / 1e18;

            totalFeeInUsdValue = feeData.desiredFee0 * 1e18 / 1e18 + feeData.desiredFee1 * 1e30 / 1e18;
        }
        // Ensure USD value of initiator fees is max INITIATOR_SHARE from total fees.
        // We add 0,001% margin that could be due to rounding errors.
        assertLe(initiatorFeeUsdValue, totalFeeInUsdValue * (INITIATOR_SHARE + (0.00001 * 1e18)) / 1e18);
    }

    /* 
    function testFuzz_Success_compoundFees_MoveTickLeft(TestVariables memory testVars, address initiator) public {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);
        vm.assume(initiator != address(usdStablePool));

        // And : Valid state
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

        // And : Move tick left.
        uint256 amount0ToSwap;
        {
            // Swap max amount to move ticks left (ensure tolerance is not exceeded when compounding afterwards)
            amount0ToSwap = 100_000_000_000_000 * 10 ** token0.decimals();

            deal(address(token0), users.liquidityProvider, amount0ToSwap, true);

            vm.startPrank(users.liquidityProvider);
            token0.approve(address(swapRouter), amount0ToSwap);

            ISwapRouter02.ExactInputSingleParams memory exactInputParams = ISwapRouter02.ExactInputSingleParams({
                tokenIn: address(token0),
                tokenOut: address(token1),
                fee: POOL_FEE,
                recipient: users.liquidityProvider,
                amountIn: amount0ToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            swapRouter.exactInputSingle(exactInputParams);

            vm.stopPrank();
        }

        // Check liquidity pre-compounding
        (,,,,,,, uint128 initialLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        (,,,,,,, uint128 newLiquidity,,,,) = nonfungiblePositionManager.positions(tokenId);
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
    } */

    function testFuzz_Success_compoundFees_NativeEth(
        TestVariables memory testVars,
        FeeGrowth memory feeData,
        address initiator
    ) public {
        // Given : initiator is not the liquidity provider.
        vm.assume(initiator != users.liquidityProvider);

        // And : Valid state
        (testVars,) = givenValidBalancedState(testVars, nativeEthPoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, nativeEthPoolKey);

        // And : Fee amounts above minimum treshold.
        feeData.desiredFee0 = bound(feeData.desiredFee0, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, ((COMPOUND_THRESHOLD / 1e18) / 2), type(uint16).max);
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

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId);

        // Then : Liquidity of position should have increased
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );
        uint256 newLiquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
        assertGt(newLiquidity, testVars.liquidity);

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 initiatorFeeToken0Calculated = feeData.desiredFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = feeData.desiredFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }
}
