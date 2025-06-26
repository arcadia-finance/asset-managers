/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { CompounderUniswapV3_Fuzz_Test } from "./_CompounderUniswapV3.fuzz.t.sol";
import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { DefaultHook } from "../../../../utils/mocks/DefaultHook.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceMock } from "../../../../utils/mocks/RouterSetPoolPriceMock.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "CompounderUniswapV3".
 */
contract ExecuteAction_CompounderUniswapV3_Fuzz_Test is CompounderUniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    DefaultHook internal strategyHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderUniswapV3_Fuzz_Test.setUp();

        strategyHook = new DefaultHook();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata rebalanceData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: account is set.
        compounder.setAccount(account_);

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Compounder.OnlyAccount.selector);
        compounder.executeAction(rebalanceData);
        vm.stopPrank();
    }

    function testFuzz_Revert_executeAction_InvalidClaimFee(
        address initiator,
        Compounder.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, ""
        );

        // And: claimfee is bigger than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, maxClaimFee + 1, type(uint64).max));

        // And: account is set.
        compounder.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        address initiator,
        Compounder.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: maxClaimFee is smaller or equal to 1e18.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));

        // And: maxSwapFee is smaller or equal to 1e18.
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, ""
        );

        // And: claimfee is smaller than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, maxClaimFee));

        // And: swapFee is bigger than maxSwapFee.
        initiatorParams.swapFee = uint64(bound(initiatorParams.swapFee, maxSwapFee + 1, type(uint64).max));

        // And: account is set.
        compounder.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        compounder.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolBeforeSwap(
        uint128 liquidityPool,
        Compounder.InitiatorParams memory initiatorParams,
        PositionState memory position,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, type(uint16).max));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, type(uint16).max));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: account is set.
        compounder.setAccount(address(account));

        // And: The pool is unbalanced.
        {
            (, uint256 lowerSqrtPriceDeviation,,,) = compounder.accountInfo(address(account));
            initiatorParams.trustedSqrtPrice = bound(
                initiatorParams.trustedSqrtPrice,
                position.sqrtPrice * 1e18 / lowerSqrtPriceDeviation + lowerSqrtPriceDeviation,
                type(uint160).max
            );
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Compounder.UnbalancedPool.selector);
        compounder.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolAfterSwap(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(
            users.liquidityProvider, address(compounder), position.id
        );

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,,) = poolUniswap.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: liqudity is not 0.
        RebalanceParams memory rebalanceParams;
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmounts(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolUniswap.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            // And: Liquidity is not 0.
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);
        }

        // And: The pool is unbalanced after the swap.
        {
            (, uint256 lowerSqrtPriceDeviation,,,) = compounder.accountInfo(address(account));
            uint256 lowerBoundSqrtPrice = initiatorParams.trustedSqrtPrice * lowerSqrtPriceDeviation / 1e18;
            vm.assume(TickMath.MIN_SQRT_PRICE < lowerBoundSqrtPrice);
            uint256 newSqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, lowerBoundSqrtPrice);

            RouterSetPoolPriceMock router = new RouterSetPoolPriceMock();
            bytes memory routerData = abi.encodeWithSelector(
                RouterSetPoolPriceMock.swap.selector, address(poolUniswap), uint160(newSqrtPrice)
            );
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Compounder.UnbalancedPool.selector);
        compounder.executeAction(actionTargetData);
    }

    function testFuzz_Revert_executeAction_InsufficientLiquidity(
        uint128 liquidityPool,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, 1e18, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(
            users.liquidityProvider, address(compounder), position.id
        );

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced and position in range.
        {
            (uint160 sqrtPrice, int24 tickCurrent,,,,,) = poolUniswap.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
            vm.assume(tickCurrent > position.tickLower && tickCurrent < position.tickUpper);
        }

        // And: liqudity is not 0.
        RebalanceParams memory rebalanceParams;
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmounts(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e10);

            rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolUniswap.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            // And: Liquidity is not 0.
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.amountOut > 10);
            vm.assume(rebalanceParams.minLiquidity > 0);
        }

        // And: Swap is not optimal resulting in little liquidity.
        {
            RouterMock router = new RouterMock();
            if (rebalanceParams.zeroToOne) {
                bytes memory routerData = abi.encodeWithSelector(
                    RouterMock.swap.selector,
                    address(token0),
                    address(token1),
                    rebalanceParams.amountIn,
                    rebalanceParams.amountOut / 10
                );
                initiatorParams.swapData = abi.encode(address(router), rebalanceParams.amountIn, routerData);
                deal(address(token1), address(router), rebalanceParams.amountOut / 10, true);
            } else {
                bytes memory routerData = abi.encodeWithSelector(
                    RouterMock.swap.selector,
                    address(token1),
                    address(token0),
                    rebalanceParams.amountIn,
                    rebalanceParams.amountOut / 10
                );
                initiatorParams.swapData = abi.encode(address(router), rebalanceParams.amountIn, routerData);
                deal(address(token0), address(router), rebalanceParams.amountOut / 10, true);
            }
        }

        // When: Calling executeAction().
        // Then: it should revert.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectRevert(Compounder.InsufficientLiquidity.selector);
        compounder.executeAction(actionTargetData);
    }

    function testFuzz_Success_executeAction(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range (has both tokens).
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(
            users.liquidityProvider, address(compounder), position.id
        );

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        {
            (uint160 sqrtPrice,,,,,,) = poolUniswap.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
        }

        // And: liqudity is not 0.
        RebalanceParams memory rebalanceParams;
        {
            // Calculate balances available on compounder to rebalance (without fees).
            (uint256 balance0, uint256 balance1) = getFeeAmounts(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e8);

            rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolUniswap.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );

            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);
        }

        // And: Swap is successful.
        {
            RouterMock router = new RouterMock();
            if (rebalanceParams.zeroToOne) {
                bytes memory routerData = abi.encodeWithSelector(
                    RouterMock.swap.selector,
                    address(token0),
                    address(token1),
                    rebalanceParams.amountIn,
                    rebalanceParams.amountOut
                );
                initiatorParams.swapData = abi.encode(address(router), rebalanceParams.amountIn, routerData);
                deal(address(token1), address(router), rebalanceParams.amountOut, true);
            } else {
                bytes memory routerData = abi.encodeWithSelector(
                    RouterMock.swap.selector,
                    address(token1),
                    address(token0),
                    rebalanceParams.amountIn,
                    rebalanceParams.amountOut
                );
                initiatorParams.swapData = abi.encode(address(router), rebalanceParams.amountIn, routerData);
                deal(address(token0), address(router), rebalanceParams.amountOut, true);
            }
        }

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(nonfungiblePositionManager), position.id);
        ActionData memory depositData = compounder.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }
}
