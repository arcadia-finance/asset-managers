/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserUniswapV4_Fuzz_Test } from "./_CloserUniswapV4.fuzz.t.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "executeAction" of contract "CloserUniswapV4".
 */
contract ExecuteAction_CloserUniswapV4_Fuzz_Test is CloserUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CloserUniswapV4_Fuzz_Test.setUp();
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

    function testFuzz_Success_executeAction_NotNative(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(positionManagerV4), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_NotNative_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_NotNative_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, false);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(positionManagerV4), position.id);
        closer.executeAction(actionTargetData);

        // Then: Position is burned.
        vm.expectRevert();
        ERC721(address(positionManagerV4)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_NotNative_WithDebtRepayment(
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 debt
    ) public {
        // Given: Create tokens and add to Arcadia.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        (token0, token1) = (token0 < token1) ? (token0, token1) : (token1, token0);
        addAssetToArcadia(address(token0), int256(1e18));
        addAssetToArcadia(address(token1), int256(1e18));

        // And: Create pool.
        poolKey = initializePoolV4(address(token0), address(token1), 2 ** 96, address(0), POOL_FEE, TICK_SPACING);
        mintPositionV4(
            poolKey,
            BOUND_TICK_LOWER / TICK_SPACING * TICK_SPACING,
            BOUND_TICK_UPPER / TICK_SPACING * TICK_SPACING,
            1e18,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And: Deploy AM.
        deployUniswapV4AM();

        // And: Configure lending pool and risk parameters.
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
        uniswapV4HooksRegistry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(defaultUniswapV4AM), type(uint112).max, 100
        );
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        position.tickLower = -10_000 / TICK_SPACING * TICK_SPACING;
        position.tickUpper = 10_000 / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e12));
        position.tickSpacing = TICK_SPACING;
        position.fee = POOL_FEE;
        position.tokens = new address[](2);
        position.tokens[0] = address(token0);
        position.tokens[1] = address(token1);
        position.id = mintPositionV4(
            poolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And: Open margin account.
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Debt in lending pool.
        debt = bound(debt, 1, 1e10);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position owned by closer (as in action).
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Configure initiator params for repayment.
        // Note: withdrawAmount must be 0 in direct executeAction tests because the withdrawal
        // happens during flashAction, not before executeAction is called.
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = debt;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
    }

    function testFuzz_Success_executeAction_IsNative(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position with native ETH as token0.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction() - use address(0) for native ETH as token0.
        bytes memory actionTargetData = abi.encode(initiator, address(0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(positionManagerV4), position.id);
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_IsNative_OnlyClaim(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position with native ETH as token0.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction() - use address(0) for native ETH as token0.
        bytes memory actionTargetData = abi.encode(initiator, address(0), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
        assertEq(depositData.assetAmounts[0], 1);
        assertEq(depositData.assetTypes[0], 2);
    }

    function testFuzz_Success_executeAction_IsNative_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position with native ETH as token0.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        deployUniswapV4AM();

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
        initiatorParams.positionManager = address(positionManagerV4);
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
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction() - use address(0) for native ETH as token0.
        bytes memory actionTargetData = abi.encode(initiator, address(0), initiatorParams);
        vm.prank(address(account));
        vm.expectEmit();
        emit Closer.Close(address(account), address(positionManagerV4), position.id);
        closer.executeAction(actionTargetData);

        // Then: Position is burned.
        vm.expectRevert();
        ERC721(address(positionManagerV4)).ownerOf(position.id);
    }

    function testFuzz_Success_executeAction_IsNative_WithDebtRepayment(
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint256 debt
    ) public {
        // Given: Create tokens and add to Arcadia. token0 is native ETH (address(0)).
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        addAssetToArcadia(address(token1), int256(1e18));
        addAssetToArcadia(address(weth9), int256(1e18));

        // And: Create pool with native ETH.
        poolKey = initializePoolV4(address(0), address(token1), 2 ** 96, address(0), POOL_FEE, TICK_SPACING);
        mintPositionV4(
            poolKey,
            BOUND_TICK_LOWER / TICK_SPACING * TICK_SPACING,
            BOUND_TICK_UPPER / TICK_SPACING * TICK_SPACING,
            1e18,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And: Deploy AM.
        deployUniswapV4AM();

        // And: Configure lending pool and risk parameters.
        LendingPoolMock lendingPoolMock = new LendingPoolMock(address(token1));
        lendingPoolMock.setRiskManager(users.riskManager);
        vm.startPrank(users.riskManager);
        registry.setRiskParameters(address(lendingPoolMock), 0, 0, type(uint64).max);
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(weth9), 0, type(uint112).max, 9000, 9500
        );
        registry.setRiskParametersOfPrimaryAsset(
            address(lendingPoolMock), address(token1), 0, type(uint112).max, 9000, 9500
        );
        uniswapV4HooksRegistry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(defaultUniswapV4AM), type(uint112).max, 100
        );
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        position.tickLower = -10_000 / TICK_SPACING * TICK_SPACING;
        position.tickUpper = 10_000 / TICK_SPACING * TICK_SPACING;
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e12));
        position.tickSpacing = TICK_SPACING;
        position.fee = POOL_FEE;
        position.tokens = new address[](2);
        position.tokens[0] = address(0);
        position.tokens[1] = address(token1);
        position.id = mintPositionV4(
            poolKey,
            position.tickLower,
            position.tickUpper,
            position.liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );

        // And: Open margin account.
        vm.prank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Closer is allowed as Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(closer);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        vm.prank(users.accountOwner);
        account.setAssetManagers(assetManagers, statuses, new bytes[](1));

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Debt in lending pool.
        debt = bound(debt, 1, 1e10);
        lendingPoolMock.setDebt(address(account), debt);

        // And: Position owned by closer (as in action).
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(closer), position.id);

        // And: Configure initiator params for repayment.
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 1, position.liquidity - 1));
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = debt;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Account is set.
        closer.setAccount(address(account));

        // When: Calling executeAction().
        bytes memory actionTargetData = abi.encode(initiator, address(token1), initiatorParams);
        vm.prank(address(account));
        ActionData memory depositData = closer.executeAction(actionTargetData);

        // Then: It should return the correct values to be deposited back into the account.
        assertEq(depositData.assets[0], address(positionManagerV4));
        assertEq(depositData.assetIds[0], position.id);
    }
}
