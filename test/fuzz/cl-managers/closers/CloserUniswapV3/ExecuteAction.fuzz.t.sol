/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserUniswapV3_Fuzz_Test } from "./_CloserUniswapV3.fuzz.t.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "executeAction" of contract "CloserUniswapV3".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ExecuteAction_CloserUniswapV3_Fuzz_Test is CloserUniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CloserUniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_executeAction_NonAccount(bytes calldata actionTargetData, address caller_) public {
        // Given: Caller is not the account.
        vm.assume(caller_ != address(account));

        // And: account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.OnlyAccount.selector);
        closer.executeAction(actionTargetData);
        vm.stopPrank();
    }

    function testFuzz_Success_executeAction_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
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
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Only claim, no liquidity change.
        initiatorParams.liquidity = 0;

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(nonfungiblePositionManager), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_DecreasePosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
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
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(nonfungiblePositionManager), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // And: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
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
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, position.liquidity, type(uint128).max));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        // Then: It should emit the correct event.
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit(address(closer));
        emit Closer.Close(address(account), address(nonfungiblePositionManager), position.id);
        closer.executeAction(actionTargetData);

        // And: Position is burned.
        vm.expectRevert();
        ERC721(address(nonfungiblePositionManager)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_WithDebtRepayment(
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 debt
    ) public {
        // Given: Pool and assets.
        initUniswapV3(2 ** 96, 1e18, POOL_FEE);
        deployUniswapV3AM();

        // And: Lending pool and risk parameters.
        LendingPoolMock lendingPoolMock = new LendingPoolMock(address(token1));
        lendingPoolMock.setRiskManager(users.riskManager);
        vm.startPrank(users.riskManager);
        registry.setRiskParameters(address(lendingPoolMock), 0, 0, type(uint64).max);
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token0), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token1), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfDerivedAM(address(lendingPoolMock), address(uniV3AM), type(uint112).max, 10_000);
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e12));
        int24 tickSpacing = poolUniswap.tickSpacing();
        (uint256 positionId,,) = addLiquidityUniV3(
            poolUniswap,
            position.liquidity,
            users.liquidityProvider,
            -10_000 / tickSpacing * tickSpacing,
            10_000 / tickSpacing * tickSpacing,
            false
        );
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(positionId);

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, position.liquidity, type(uint128).max));

        // And: debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

        // And: Position has debt.
        debt = bound(debt, 1, 1e8);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), positionId);

        // And: Withdraw amount is minted to the Closer.
        deal(address(token1), address(closer), initiatorParams.withdrawAmount);

        // And: Account is set and is a margin account.
        closer.setAccount(address(account));
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Debt should be reduced correctly.
        // If maxRepayAmount is 0, debt stays the same. Otherwise debt is reduced.
        if (initiatorParams.maxRepayAmount == 0) {
            assertEq(lendingPoolMock.debt(address(account)), debt);
        } else {
            assertLt(lendingPoolMock.debt(address(account)), debt);
        }
    }
}
