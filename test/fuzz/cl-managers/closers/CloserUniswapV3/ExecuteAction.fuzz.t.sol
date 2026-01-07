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

    function testFuzz_Success_executeAction(
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
        deployUniswapV3AM();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Configure initiator params.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Position owned by closer (as in action).
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(nonfungiblePositionManager), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(nonfungiblePositionManager));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
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
        deployUniswapV3AM();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Only claim, no liquidity change (liquidity == 0).
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = 0;
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Position owned by closer (as in action).
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
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
        deployUniswapV3AM();

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Burn all liquidity (liquidity >= position.liquidity).
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = position.liquidity;
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Position owned by closer (as in action).
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(nonfungiblePositionManager), position.id);
        closer.executeAction(actionTargetData);

        // Then: Position is burned.
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
        registry.setRiskParametersOfDerivedAM(address(lendingPoolMock), address(uniV3AM), type(uint112).max, 100);
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

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Configure initiator params.
        initiatorParams.positionManager = address(nonfungiblePositionManager);
        // Safe cast: positionId is bounded by NFT minting which won't exceed uint96.max.
        // forge-lint: disable-next-line(unsafe-typecast)
        initiatorParams.id = uint96(positionId);
        initiatorParams.liquidity = position.liquidity;
        initiatorParams.maxRepayAmount = type(uint256).max;
        initiatorParams.withdrawAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Set debt.
        debt = bound(debt, 1, 1e8);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: The Closer owns the position.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(closer), positionId);

        // And: account is set and has margin account.
        closer.setAccount(address(account));
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        closer.executeAction(actionTargetData);

        // Then: Debt should be fully repaid.
        assertEq(lendingPoolMock.debt(address(account)), 0);
    }
}
