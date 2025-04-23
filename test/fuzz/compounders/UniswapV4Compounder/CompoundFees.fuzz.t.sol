/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FixedPoint128.sol";
import { PositionInfo } from "../../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";
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

    function testFuzz_Revert_compoundFees_Reentered(address random, uint256 tokenId, uint160 sqrtPriceX96) public {
        // Given: A rebalance is ongoing.
        vm.assume(random != address(0));
        compounder.setAccount(random);

        // When: Calling compoundFees().
        // Then: It should revert.
        vm.expectRevert(UniswapV4Compounder.Reentered.selector);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);
    }

    function testFuzz_Revert_compoundFees_InitiatorNotValid(address notInitiator, uint256 tokenId, uint160 sqrtPriceX96)
        public
    {
        // Given: The caller is not the initiator.
        vm.assume(initiator != notInitiator);

        // When: Calling compoundFees().
        // Then: It should revert.
        vm.prank(notInitiator);
        vm.expectRevert(UniswapV4Compounder.InitiatorNotValid.selector);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);
    }

    function testFuzz_Success_compoundFees(TestVariables memory testVars, FeeGrowth memory feeData) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        testVars.liquidity = stateView.getLiquidity(stablePoolKey.toId());

        // And : Fee amounts above minimum treshold.
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

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(stablePoolKey.toId());

        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );

        // And : Assume positive fees.
        {
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (uint256 amount0, uint256 amount1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            vm.assume(amount0 > 0 || amount1 > 0);
        }

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);

        // Then : Liquidity of position should have increased
        {
            uint256 newLiquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            assertGt(newLiquidity, testVars.liquidity);
        }

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = token0.balanceOf(initiator);
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 initiatorFeeToken0Calculated = feeData.desiredFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = feeData.desiredFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }

    function testFuzz_Success_compoundFees_MoveTickRight(TestVariables memory testVars, FeeGrowth memory feeData)
        public
    {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // And : Fee amounts above minimum treshold.
        feeData.desiredFee0 = bound(feeData.desiredFee0, 5, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 5, type(uint16).max);
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
            (uint160 trustedSqrtPriceX96, int24 currentTick,,) = stateView.getSlot0(stablePoolKey.toId());
            (UniswapV4Compounder.PositionState memory position,) =
                compounder.getPositionState(tokenId, trustedSqrtPriceX96, initiator);
            int24 upperBoundTick = TickMath.getTickAtSqrtPrice(uint160(position.upperBoundSqrtPriceX96));
            int256 tickDelta = (int256(upperBoundTick - currentTick) * 9500) / 10_000;
            int24 newTick = currentTick + int24(tickDelta);
            poolManager.setCurrentPrice(stablePoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));
        }

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(stablePoolKey.toId());

        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );

        // And : Assume positive fees.
        {
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (uint256 amount0, uint256 amount1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            vm.assume(amount0 > 0 || amount1 > 0);
        }

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);

        // Then : Liquidity of position should have increased
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

    function testFuzz_Success_compoundFees_MoveTickLeft(TestVariables memory testVars, FeeGrowth memory feeData)
        public
    {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars, stablePoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, stablePoolKey);

        // And : Fee amounts above minimum treshold.
        feeData.desiredFee0 = bound(feeData.desiredFee0, 5, type(uint16).max);
        feeData.desiredFee1 = bound(feeData.desiredFee1, 5, type(uint16).max);
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

        // And : Move tick left.
        {
            (uint160 trustedSqrtPriceX96, int24 currentTick,,) = stateView.getSlot0(stablePoolKey.toId());
            (UniswapV4Compounder.PositionState memory position,) =
                compounder.getPositionState(tokenId, trustedSqrtPriceX96, initiator);
            int24 upperBoundTick = TickMath.getTickAtSqrtPrice(uint160(position.upperBoundSqrtPriceX96));
            int256 tickDelta = (int256(upperBoundTick - currentTick) * 9500) / 10_000;
            int24 newTick = currentTick - int24(tickDelta);
            poolManager.setCurrentPrice(stablePoolKey.toId(), newTick, TickMath.getSqrtPriceAtTick(newTick));
        }

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(stablePoolKey.toId());
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );

        // And : Assume positive fees.
        {
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(stablePoolKey.toId(), positionId);
            (uint256 amount0, uint256 amount1) = getFeeAmounts(tokenId, stablePoolKey.toId(), info, liquidity);
            vm.assume(amount0 > 0 || amount1 > 0);
        }

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);

        // Then : Liquidity of position should have increased
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

    function testFuzz_Success_compoundFees_NativeEth(TestVariables memory testVars, FeeGrowth memory feeData) public {
        // Given : Valid state
        (testVars,) = givenValidBalancedState(testVars, nativeEthPoolKey);

        // And : State is persisted
        uint256 tokenId = setState(testVars, nativeEthPoolKey);

        testVars.liquidity = stateView.getLiquidity(nativeEthPoolKey.toId());

        // And : Fee amounts above minimum treshold (in $).
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

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(nativeEthPoolKey.toId());
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), testVars.tickLower, testVars.tickUpper, bytes32(tokenId))
        );

        // And : Assume positive fees.
        {
            (, PositionInfo info) = positionManagerV4.getPoolAndPositionInfo(tokenId);
            uint128 liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
            (uint256 amount0, uint256 amount1) = getFeeAmounts(tokenId, nativeEthPoolKey.toId(), info, liquidity);
            vm.assume(amount0 > 0 || amount1 > 0);
        }

        uint256 initInitiatorBalance = initiator.balance;

        // When : Calling compoundFees()
        vm.prank(initiator);
        compounder.compoundFees(address(account), tokenId, sqrtPriceX96);

        // Then : Liquidity of position should have increased
        uint256 newLiquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);
        assertGt(newLiquidity, testVars.liquidity);

        // And : initiatorFees should never be bigger than the calculated share plus a small bonus due to rounding errors in.
        uint256 initiatorFeesToken0 = initiator.balance - initInitiatorBalance;
        uint256 initiatorFeesToken1 = token1.balanceOf(initiator);

        uint256 initiatorFeeToken0Calculated = feeData.desiredFee0 * (INITIATOR_SHARE + TOLERANCE) / 1e18;
        uint256 initiatorFeeToken1Calculated = feeData.desiredFee1 * (INITIATOR_SHARE + TOLERANCE) / 1e18;

        assertLe(initiatorFeesToken0, initiatorFeeToken0Calculated);
        assertLe(initiatorFeesToken1, initiatorFeeToken1Calculated);
    }
}
