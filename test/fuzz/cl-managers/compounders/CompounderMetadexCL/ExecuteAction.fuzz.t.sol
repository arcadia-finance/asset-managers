/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Compounder } from "../../../../../src/cl-managers/compounders/Compounder.sol";
import { CompounderMetadexCL_Fuzz_Test } from "./_CompounderMetadexCL.fuzz.t.sol";
import { ERC20 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FullMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/FullMath.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { RebalanceLogic, RebalanceParams } from "../../../../../src/cl-managers/libraries/RebalanceLogic.sol";
import { RouterMock } from "../../../../utils/mocks/RouterMock.sol";
import { RouterSetPoolPriceMock } from "../../../../utils/mocks/RouterSetPoolPriceMock.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_executeAction" of contract "CompounderSlipstream", on Metadex CL.
 */
// forge-lint: disable-next-item(divide-before-multiply,erc20-unchecked-transfer,unsafe-typecast)
contract ExecuteAction_CompounderMetadexCL_Fuzz_Test is CompounderMetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CompounderMetadexCL_Fuzz_Test.setUp();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    // Stages a pool with an in range position that carries both tokens.
    function setInRangePosition(uint128 liquidityPool, PositionState memory position, bool staked) internal {
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e20, 1e25));
        setPoolState(liquidityPool, position, staked);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
    }

    // Encodes a router swap that returns exactly the requested amountOut.
    function setSwapData(Compounder.InitiatorParams memory initiatorParams, RebalanceParams memory rebalanceParams)
        internal
    {
        setSwapData(initiatorParams, rebalanceParams, rebalanceParams.amountOut);
    }

    function setSwapData(
        Compounder.InitiatorParams memory initiatorParams,
        RebalanceParams memory rebalanceParams,
        uint256 amountOut
    ) internal {
        RouterMock router = new RouterMock();
        (address tokenIn, address tokenOut) =
            rebalanceParams.zeroToOne ? (address(token0), address(token1)) : (address(token1), address(token0));
        bytes memory routerData =
            abi.encodeWithSelector(RouterMock.swap.selector, tokenIn, tokenOut, rebalanceParams.amountIn, amountOut);
        initiatorParams.swapData = abi.encode(address(router), rebalanceParams.amountIn, routerData);
        deal(tokenOut, address(router), amountOut, true);
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_executeAction_NonAccount(bytes calldata compoundData, address account_, address caller_)
        public
    {
        // Given: Caller is not the account.
        vm.assume(caller_ != account_);

        // And: Account is set.
        compounder.setAccount(account_);

        // When: Calling executeAction.
        vm.prank(caller_);
        vm.expectRevert(Compounder.OnlyAccount.selector);
        // Then: It reverts.
        compounder.executeAction(compoundData);
    }

    function testFuzz_Revert_executeAction_InvalidClaimFee(
        address initiator,
        Compounder.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: The fee caps are below 100%.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, ""
        );

        // And: claimFee is bigger than maxClaimFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, maxClaimFee + 1, type(uint64).max));

        // And: Account is set.
        compounder.setAccount(address(account));

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        // Then: It reverts.
        compounder.executeAction(abi.encode(initiator, initiatorParams));
    }

    function testFuzz_Revert_executeAction_InvalidSwapFee(
        address initiator,
        Compounder.InitiatorParams memory initiatorParams,
        uint256 maxClaimFee,
        uint256 maxSwapFee
    ) public {
        // Given: The fee caps are below 100%.
        maxClaimFee = uint64(bound(maxClaimFee, 0, 1e18));
        maxSwapFee = uint64(bound(maxSwapFee, 0, 1e18));

        // And: Account info is set.
        vm.prank(account.owner());
        compounder.setAccountInfo(
            address(account), initiator, maxClaimFee, maxSwapFee, MAX_TOLERANCE, MIN_LIQUIDITY_RATIO, ""
        );

        // And: claimFee is below maxClaimFee but swapFee is bigger than maxSwapFee.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, maxClaimFee));
        initiatorParams.swapFee = uint64(bound(initiatorParams.swapFee, maxSwapFee + 1, type(uint64).max));

        // And: Account is set.
        compounder.setAccount(address(account));

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Compounder.InvalidValue.selector);
        // Then: It reverts.
        compounder.executeAction(abi.encode(initiator, initiatorParams));
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
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);
        initiatorParams.positionManager = address(metadex03PositionManager);
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

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is unbalanced.
        {
            (,,, uint256 lowerSqrtPriceDeviation,) = compounder.accountInfo(address(account));
            initiatorParams.trustedSqrtPrice = bound(
                initiatorParams.trustedSqrtPrice,
                position.sqrtPrice * 1e18 / lowerSqrtPriceDeviation + lowerSqrtPriceDeviation,
                type(uint160).max
            );
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Compounder.UnbalancedPool.selector);
        // Then: It reverts.
        compounder.executeAction(abi.encode(initiator, initiatorParams));
    }

    function testFuzz_Revert_executeAction_UnbalancedPoolAfterSwap(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
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
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: Liquidity is not 0.
        {
            (uint256 balance0, uint256 balance1) = getFeeAmountsMetadex03CL(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e10);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
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

        // And: The pool is unbalanced after the swap.
        {
            (,,, uint256 lowerSqrtPriceDeviation,) = compounder.accountInfo(address(account));
            uint256 lowerBoundSqrtPrice = initiatorParams.trustedSqrtPrice * lowerSqrtPriceDeviation / 1e18;
            vm.assume(TickMath.MIN_SQRT_PRICE < lowerBoundSqrtPrice);
            uint256 newSqrtPrice = bound(position.sqrtPrice, TickMath.MIN_SQRT_PRICE, lowerBoundSqrtPrice);

            RouterSetPoolPriceMock router = new RouterSetPoolPriceMock();
            bytes memory routerData =
                abi.encodeWithSelector(RouterSetPoolPriceMock.swap.selector, address(poolCl), uint160(newSqrtPrice));
            initiatorParams.swapData = abi.encode(address(router), 0, routerData);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Compounder.UnbalancedPool.selector);
        // Then: It reverts.
        compounder.executeAction(abi.encode(initiator, initiatorParams));
    }

    function testFuzz_Revert_executeAction_InsufficientLiquidity(
        uint128 liquidityPool,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info requires the full liquidity ratio.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, 1e18, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced and the position is in range.
        {
            (uint160 sqrtPrice, int24 tickCurrent,,,,) = poolCl.slot0();
            initiatorParams.trustedSqrtPrice = sqrtPrice;
            vm.assume(tickCurrent > position.tickLower && tickCurrent < position.tickUpper);
        }

        // And: The swap is not optimal, resulting in too little liquidity.
        {
            (uint256 balance0, uint256 balance1) = getFeeAmountsMetadex03CL(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e10);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.amountOut > 10);
            vm.assume(rebalanceParams.minLiquidity > 0);

            setSwapData(initiatorParams, rebalanceParams, rebalanceParams.amountOut / 10);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectRevert(Compounder.InsufficientLiquidity.selector);
        // Then: It reverts.
        compounder.executeAction(abi.encode(initiator, initiatorParams));
    }

    function testFuzz_Success_executeAction_MetadexCL(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
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
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap is successful.
        {
            (uint256 balance0, uint256 balance1) = getFeeAmountsMetadex03CL(position.id);
            balance0 = initiatorParams.amount0 + balance0 - balance0 * initiatorParams.claimFee / 1e18;
            balance1 = initiatorParams.amount1 + balance1 - balance1 * initiatorParams.claimFee / 1e18;
            vm.assume(balance0 + balance1 > 1e10);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);

            setSwapData(initiatorParams, rebalanceParams);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(metadex03PositionManager), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);
    }

    function testFuzz_Success_executeAction_MetadexCL_Token0WithoutFees(
        uint128 liquidityPool,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
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
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: The initiator is not the Compounder.
        vm.assume(initiator != address(compounder));

        // And: Compounder has only token0, worth at least 1e8 token1, and no fees.
        {
            uint256 minAmount0 = FullMath.mulDivRoundingUp(1e8, 1 << 192, position.sqrtPrice * position.sqrtPrice);
            vm.assume(minAmount0 <= 1e18);
            initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, minAmount0, 1e18));
        }
        initiatorParams.amount1 = 0;
        deal(address(token0), address(compounder), initiatorParams.amount0, true);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap of token0 to token1 is successful.
        {
            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                initiatorParams.amount0,
                0
            );
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);

            setSwapData(initiatorParams, rebalanceParams);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(metadex03PositionManager), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);

        // And: All token0 and token1 left in the Compounder are returned to the Account.
        assertEq(token0.allowance(address(compounder), address(account)), token0.balanceOf(address(compounder)));
        assertEq(token1.allowance(address(compounder), address(account)), token1.balanceOf(address(compounder)));
    }

    function testFuzz_Success_executeAction_MetadexCL_Token1WithoutFees(
        uint128 liquidityPool,
        PositionState memory position,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
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
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: The initiator is not the Compounder.
        vm.assume(initiator != address(compounder));

        // And: Compounder has only token1, worth at least 1e8 token0, and no fees.
        {
            uint256 minAmount1 = FullMath.mulDivRoundingUp(1e8, position.sqrtPrice * position.sqrtPrice, 1 << 192);
            vm.assume(minAmount1 <= 1e18);
            initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, minAmount1, 1e18));
        }
        initiatorParams.amount0 = 0;
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap of token1 to token0 is successful.
        {
            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                0,
                initiatorParams.amount1
            );
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);

            setSwapData(initiatorParams, rebalanceParams);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(metadex03PositionManager), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The position is returned to the account.
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);

        // And: All token0 and token1 left in the Compounder are returned to the Account.
        assertEq(token0.allowance(address(compounder), address(account)), token0.balanceOf(address(compounder)));
        assertEq(token1.allowance(address(compounder), address(account)), token1.balanceOf(address(compounder)));
    }

    function testFuzz_Success_executeAction_MetadexCL_ClaimOnly_FullClaimFee(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid position in range.
        setInRangePosition(liquidityPool, position, false);
        initiatorParams.positionManager = address(metadex03PositionManager);
        initiatorParams.id = uint96(position.id);

        // And: Account info is set, with a maximum claim fee of 100%.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, 1e18, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: The initiator claims all fees.
        initiatorParams.claimFee = 1e18;
        initiatorParams.swapFee = uint64(bound(initiatorParams.swapFee, 0, MAX_FEE));

        // And: The Compounder owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(metadex03PositionManager))
            .transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: The initiator is not the Compounder or the pool.
        vm.assume(initiator != address(compounder));
        vm.assume(initiator != address(poolCl));

        // And: Compounder has no balances.
        initiatorParams.amount0 = 0;
        initiatorParams.amount1 = 0;

        // And: The position has fees in both tokens.
        feeSeed = bound(feeSeed, type(uint8).max, type(uint48).max);
        generateFees(feeSeed, feeSeed);
        (uint256 fee0, uint256 fee1) = getFeeAmountsMetadex03CL(position.id);
        vm.assume(fee0 > 0);
        vm.assume(fee1 > 0);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The token balances of the initiator are known.
        uint256 initiatorBalance0 = token0.balanceOf(initiator);
        uint256 initiatorBalance1 = token1.balanceOf(initiator);

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(metadex03PositionManager), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: Only the position is returned to the account.
        assertEq(depositData.assets.length, 1);
        assertEq(depositData.assets[0], address(metadex03PositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The liquidity of the position is unchanged.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertEq(liquidity, position.liquidity);

        // And: The initiator received all claimed fees.
        assertEq(token0.balanceOf(initiator), initiatorBalance0 + fee0);
        assertEq(token1.balanceOf(initiator), initiatorBalance1 + fee1);

        // And: No token0 or token1 is left in the Compounder.
        assertEq(token0.balanceOf(address(compounder)), 0);
        assertEq(token1.balanceOf(address(compounder)), 0);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_executeAction_StakedMetadexCLAM_RewardTokenNotToken0Or1(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        vm.assume(initiator != address(0));

        // Given: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        initiatorParams.id = uint96(position.id);

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the staked position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: Compounder has balances.
        initiatorParams.amount0 = uint128(bound(initiatorParams.amount0, 0, 1e18));
        initiatorParams.amount1 = uint128(bound(initiatorParams.amount1, 0, 1e18));
        vm.assume(uint256(initiatorParams.amount0) + initiatorParams.amount1 > type(uint8).max);
        deal(address(token0), address(compounder), initiatorParams.amount0, true);
        deal(address(token1), address(compounder), initiatorParams.amount1, true);

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint48).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // And: The swap is successful.
        {
            vm.assume(uint256(initiatorParams.amount0) + initiatorParams.amount1 > 1e10);

            RebalanceParams memory rebalanceParams = RebalanceLogic._getRebalanceParams(
                1e18,
                poolCl.fee(),
                initiatorParams.swapFee,
                initiatorParams.trustedSqrtPrice,
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                initiatorParams.amount0,
                initiatorParams.amount1
            );
            vm.assume(rebalanceParams.amountIn > 0);
            vm.assume(rebalanceParams.minLiquidity > 0);

            setSwapData(initiatorParams, rebalanceParams);
        }

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(stakedMetadex03CLAM), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The staked position is returned to the account.
        assertEq(depositData.assets[0], address(stakedMetadex03CLAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);

        // And: The claimed ReceiptToken is returned as a third asset.
        uint256 rewardDeposited;
        for (uint256 i = 1; i < depositData.assets.length; ++i) {
            if (depositData.assets[i] == receiptToken) rewardDeposited = depositData.assetAmounts[i];
        }
        assertGt(rewardDeposited, 0);
        assertEq(rewardDeposited, ERC20(receiptToken).balanceOf(address(compounder)));

        // And: The liquidity of the position increased.
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertGt(liquidity, position.liquidity);
    }

    // forge-lint: disable-next-item(mixed-case-function)
    function testFuzz_Success_executeAction_StakedMetadexCLAM_ClaimOnly(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 rewards,
        Compounder.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 tolerance
    ) public {
        // Given: A valid staked position in range.
        setInRangePosition(liquidityPool, position, true);
        initiatorParams.positionManager = address(stakedMetadex03CLAM);
        initiatorParams.id = uint96(position.id);

        // And: The position is staked.
        stakeInStakedMetadexCLAM(position.id);

        // And: The initiator does not hold the reward token and can receive it.
        vm.assume(initiator != address(0));
        vm.assume(initiator != address(compounder));
        vm.assume(initiator != address(gauge));

        // And: Account info is set.
        tolerance = bound(tolerance, 0.001 * 1e18, MAX_TOLERANCE);
        vm.prank(account.owner());
        compounder.setAccountInfo(address(account), initiator, MAX_FEE, MAX_FEE, tolerance, MIN_LIQUIDITY_RATIO, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_FEE));
        initiatorParams.swapFee = initiatorParams.claimFee;

        // And: The Compounder owns the staked position.
        vm.prank(users.liquidityProvider);
        ERC721(address(stakedMetadex03CLAM)).transferFrom(users.liquidityProvider, address(compounder), position.id);

        // And: Compounder has no balances.
        initiatorParams.amount0 = 0;
        initiatorParams.amount1 = 0;

        // And: The position earned rewards.
        rewards = bound(rewards, 1e3, type(uint64).max);
        accrueRewards(rewards, FullMath.mulDiv(rewards, 1 << 128, position.liquidity));
        rewards = stakedMetadex03CLAM.rewardOf(position.id);

        // And: Account is set.
        compounder.setAccount(address(account));

        // And: The pool is balanced.
        (initiatorParams.trustedSqrtPrice,,,,,) = poolCl.slot0();

        // When: Calling executeAction.
        vm.prank(address(account));
        vm.expectEmit();
        emit Compounder.Compound(address(account), address(stakedMetadex03CLAM), position.id);
        ActionData memory depositData = compounder.executeAction(abi.encode(initiator, initiatorParams));

        // Then: The staked position and the rewards net of the claimFee are returned to the account.
        uint256 fee = rewards * initiatorParams.claimFee / 1e18;
        assertEq(depositData.assets.length, 2);
        assertEq(depositData.assets[0], address(stakedMetadex03CLAM));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
        assertEq(depositData.assets[1], receiptToken);
        assertEq(depositData.assetIds[1], 0);
        assertEq(depositData.assetAmounts[1], rewards - fee);
        assertEq(depositData.assetTypes[1], 1);

        // And: The Account is approved for the position and the net rewards.
        assertEq(ERC721(address(stakedMetadex03CLAM)).getApproved(position.id), address(account));
        assertEq(ERC20(receiptToken).balanceOf(address(compounder)), rewards - fee);
        assertEq(ERC20(receiptToken).allowance(address(compounder), address(account)), rewards - fee);

        // And: The initiator received the claimFee share of the rewards.
        assertEq(ERC20(receiptToken).balanceOf(initiator), fee);

        // And: The position is staked again, with unchanged liquidity.
        assertEq(ERC721(address(stakedMetadex03CLAM)).ownerOf(position.id), address(compounder));
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position.id), address(gauge));
        (,,,,,,, uint128 liquidity,,,,) = metadex03PositionManager.positions(position.id);
        assertEq(liquidity, position.liquidity);
    }
}
