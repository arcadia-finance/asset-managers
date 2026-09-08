/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ArcadiaOracle } from "../../../../../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { BitPackingLib } from "../../../../../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserUniswapV4_Fuzz_Test } from "./_CloserUniswapV4.fuzz.t.sol";
import { ERC20Mock } from "../../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { LendingPoolMock } from "../../../../utils/mocks/LendingPoolMock.sol";
import { NativeTokenAM } from "../../../../../lib/accounts-v2/src/asset-modules/native-token/NativeTokenAM.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "close" of contract "CloserUniswapV4".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Close_CloserUniswapV4_Fuzz_Test is CloserUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CloserUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_close_Paused(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Closer is paused.
        vm.prank(users.owner);
        closer.setPauseFlag(true);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Guardian.Paused.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_Reentered(
        address account_,
        Closer.InitiatorParams memory initiatorParams,
        address caller_
    ) public {
        // Given: Account is not address(0).
        vm.assume(account_ != address(0));

        // And: account is set (triggering reentry guard).
        closer.setAccount(account_);

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.Reentered.selector);
        closer.close(account_, initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidInitiator(Closer.InitiatorParams memory initiatorParams, address caller_)
        public
    {
        // Given: Caller is not address(0).
        vm.assume(caller_ != address(0));

        // When: Calling close().
        // Then: it should revert.
        vm.startPrank(caller_);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidPositionManager(
        Closer.InitiatorParams memory initiatorParams,
        address invalidPositionManager
    ) public {
        // Given: An invalid position manager (not whitelisted).
        vm.assume(invalidPositionManager != address(positionManagerV4));
        initiatorParams.positionManager = invalidPositionManager;

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // When: Calling close() with invalid position manager.
        // Then: it should revert.
        vm.startPrank(users.accountOwner);
        vm.expectRevert(Closer.InvalidPositionManager.selector);
        closer.close(address(account), initiatorParams);
        vm.stopPrank();
    }

    function testFuzz_Revert_close_InvalidClaimFee(
        uint96 id,
        uint256 withdrawAmount,
        uint256 maxRepayAmount,
        uint256 claimFee,
        uint128 liquidity
    ) public {
        // Given: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // Given: Claim fee is invalid (above maximum).
        claimFee = bound(claimFee, MAX_CLAIM_FEE + 1, type(uint256).max);

        Closer.InitiatorParams memory initiatorParams = Closer.InitiatorParams({
            positionManager: address(positionManagerV4),
            id: id,
            withdrawAmount: withdrawAmount,
            maxRepayAmount: maxRepayAmount,
            claimFee: claimFee,
            liquidity: liquidity
        });

        // When: Calling close with invalid claimFee.
        // Then: It should revert.
        vm.prank(users.accountOwner);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_InvalidWithdrawAmount(
        uint96 id,
        uint256 withdrawAmount,
        uint256 maxRepayAmount,
        uint256 claimFee,
        uint128 liquidity
    ) public {
        // Given: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), users.accountOwner, MAX_CLAIM_FEE, "");

        // Given: Fees are valid.
        claimFee = bound(claimFee, 0, MAX_CLAIM_FEE);

        // Given: withdrawAmount is greater than maxRepayAmount.
        maxRepayAmount = bound(maxRepayAmount, 0, type(uint256).max - 1);
        withdrawAmount = bound(withdrawAmount, maxRepayAmount + 1, type(uint256).max);

        Closer.InitiatorParams memory initiatorParams = Closer.InitiatorParams({
            positionManager: address(positionManagerV4),
            id: id,
            withdrawAmount: withdrawAmount,
            maxRepayAmount: maxRepayAmount,
            claimFee: claimFee,
            liquidity: liquidity
        });

        // When: Calling close with invalid withdrawAmount.
        // Then: It should revert.
        vm.prank(users.accountOwner);
        vm.expectRevert(Closer.InvalidValue.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Revert_close_ChangeAccountOwnership(
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        address newOwner
    ) public canReceiveERC721(newOwner) {
        // Given: newOwner is not the zero address and differs from the actual owner.
        vm.assume(newOwner != address(0));
        vm.assume(newOwner != users.accountOwner);
        vm.assume(newOwner != address(account));
        vm.assume(initiator != address(0));

        // And: Account info is set.
        vm.prank(account.owner());
        closer.setAccountInfo(address(account), initiator, MAX_CLAIM_FEE, "");

        // And: Fees are valid.
        initiatorParams.claimFee = 0;

        // And: Account is transferred to newOwner.
        vm.prank(users.accountOwner);
        factory.safeTransferFrom(users.accountOwner, newOwner, address(account));

        // When: calling close.
        // Then: it should revert.
        vm.prank(initiator);
        vm.expectRevert(Closer.InvalidInitiator.selector);
        closer.close(address(account), initiatorParams);
    }

    function testFuzz_Success_close_NotNative(
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
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: UniswapV4 is allowed.
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);

        // And: Account owns the position.
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);
        assets_[0] = address(positionManagerV4);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        vm.startPrank(users.accountOwner);
        ERC721(address(positionManagerV4)).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is back in account if not fully burned.
        if (initiatorParams.liquidity < position.liquidity) {
            assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));
        }
    }

    function testFuzz_Success_close_IsNative(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position with native token.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: UniswapV4 is allowed.
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity is partially decreased (not full burn).
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity - 1));

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);

        // And: Account owns the position.
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);
        assets_[0] = address(positionManagerV4);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        vm.startPrank(users.accountOwner);
        ERC721(address(positionManagerV4)).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is back in account.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position.id), address(account));
    }

    function testFuzz_Success_close_IsNative_BurnPosition(
        uint128 liquidityPool,
        PositionState memory position,
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator
    ) public {
        // Given: Valid pool and position with native token.
        givenValidPoolState(liquidityPool, position);
        liquidityPool = uint128(bound(liquidityPool, 1e25, 1e30));
        setPoolState(liquidityPool, position, true);
        position.tickLower = int24(bound(position.tickLower, BOUND_TICK_LOWER, position.tickCurrent - 1));
        position.tickLower = position.tickLower / position.tickSpacing * position.tickSpacing;
        position.tickUpper = int24(bound(position.tickUpper, position.tickCurrent, BOUND_TICK_UPPER));
        position.tickUpper = position.tickCurrent + (position.tickCurrent - position.tickLower);
        position.liquidity = uint128(bound(position.liquidity, 1e10, 1e15));
        setPositionState(position);
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

        // And: UniswapV4 is allowed.
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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Position is fully burned.
        initiatorParams.liquidity = position.liquidity;

        // And: No debt repayment.
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);

        // And: Account owns the position.
        address[] memory assets_ = new address[](1);
        uint256[] memory assetIds_ = new uint256[](1);
        uint256[] memory assetAmounts_ = new uint256[](1);
        assets_[0] = address(positionManagerV4);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        vm.startPrank(users.accountOwner);
        ERC721(address(positionManagerV4)).approve(address(account), position.id);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Position is burned.
        vm.expectRevert();
        ERC721(address(positionManagerV4)).ownerOf(position.id);
    }

    function testFuzz_Success_close_NotNative_WithDebtRepayment(
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
            address(lendingPoolMock), address(defaultUniswapV4AM), type(uint112).max, 10_000
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
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);

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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));

        // And: Debt is repaid.
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

        // And: Account owns the position, has withdrawAmount of numeraire, and is a margin account.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, position.id);
        deal(address(token1), users.accountOwner, initiatorParams.withdrawAmount);
        address[] memory assets_ = new address[](2);
        uint256[] memory assetIds_ = new uint256[](2);
        uint256[] memory assetAmounts_ = new uint256[](2);
        assets_[0] = address(positionManagerV4);
        assetIds_[0] = position.id;
        assetAmounts_[0] = 1;
        assets_[1] = address(token1);
        assetIds_[1] = 0;
        assetAmounts_[1] = initiatorParams.withdrawAmount;
        vm.startPrank(users.accountOwner);
        account.openMarginAccount(address(lendingPoolMock));
        ERC721(address(positionManagerV4)).approve(address(account), position.id);
        token1.approve(address(account), initiatorParams.withdrawAmount);
        account.deposit(assets_, assetIds_, assetAmounts_);
        vm.stopPrank();

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Debt should be reduced or stay the same.
        assertLe(lendingPoolMock.debt(address(account)), debt);
    }

    function testFuzz_Success_close_IsNative_WithDebtRepayment(
        uint256 feeSeed,
        Closer.InitiatorParams memory initiatorParams,
        address initiator,
        uint128 liquidity,
        uint256 debt
    ) public {
        // Given: Create token1 and add to Arcadia.
        token1 = new ERC20Mock("TokenB", "TOKB", 18);
        addAssetToArcadia(address(token1), int256(1e18));

        // And: Create single ETH oracle and use it for both weth9 (erc20AM) and address(0) (nativeTokenAM).
        {
            ArcadiaOracle ethOracle = initMockedOracle(18, "ETH / USD", int256(1e18));
            vm.startPrank(chainlinkOM.owner());
            chainlinkOM.addOracle(address(ethOracle), "ETH", "USD", 2 days);
            vm.stopPrank();

            uint80[] memory oracleEthToUsdArr = new uint80[](1);
            oracleEthToUsdArr[0] = uint80(chainlinkOM.oracleToOracleId(address(ethOracle)));

            // Add weth9 via erc20AM using the ETH oracle.
            vm.startPrank(registry.owner());
            erc20AM.addAsset(address(weth9), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
            vm.stopPrank();

            // Deploy native AM and add address(0) using the same ETH oracle.
            vm.startPrank(users.owner);
            nativeTokenAM = new NativeTokenAM(users.owner, address(registry), 18);
            registry.addAssetModule(address(nativeTokenAM));
            nativeTokenAM.addAsset(address(0), BitPackingLib.pack(BA_TO_QA_SINGLE, oracleEthToUsdArr));
            vm.stopPrank();
        }

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

        // And: Deploy UniswapV4 AM.
        deployUniswapV4AM();

        // And: Lending pool and risk parameters. Numeraire is token1 (not native ETH).
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
        registry.setRiskParametersOfPrimaryAsset(address(lendingPoolMock), address(0), 0, type(uint112).max, 9000, 9500);
        uniswapV4HooksRegistry.setRiskParametersOfDerivedAM(
            address(lendingPoolMock), address(defaultUniswapV4AM), type(uint112).max, 10_000
        );
        vm.stopPrank();

        // And: Create position with bounded liquidity.
        liquidity = uint128(bound(liquidity, 1e10, 1e12));
        uint256 positionId = mintPositionV4(
            poolKey,
            -10_000 / TICK_SPACING * TICK_SPACING,
            10_000 / TICK_SPACING * TICK_SPACING,
            liquidity,
            type(uint128).max,
            type(uint128).max,
            users.liquidityProvider
        );
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(positionId);

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

        // And: Fees are valid.
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

        // And: Liquidity might be (fully) decreased.
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, liquidity));

        // And: Debt is repaid.
        initiatorParams.maxRepayAmount = bound(initiatorParams.maxRepayAmount, 0, type(uint256).max);
        initiatorParams.withdrawAmount = bound(
            initiatorParams.withdrawAmount,
            0,
            initiatorParams.maxRepayAmount < 1e8 ? initiatorParams.maxRepayAmount : 1e8
        );

        // And: Position has fees.
        feeSeed = uint256(bound(feeSeed, type(uint8).max, type(uint48).max));
        generateFees(feeSeed, feeSeed);

        // And: Account owns the position, has withdrawAmount of numeraire (token1), and is a margin account.
        {
            vm.prank(users.liquidityProvider);
            ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, users.accountOwner, positionId);
            deal(address(token1), users.accountOwner, initiatorParams.withdrawAmount);
            address[] memory assets_ = new address[](2);
            uint256[] memory assetIds_ = new uint256[](2);
            uint256[] memory assetAmounts_ = new uint256[](2);
            assets_[0] = address(positionManagerV4);
            assetIds_[0] = positionId;
            assetAmounts_[0] = 1;
            assets_[1] = address(token1);
            assetIds_[1] = 0;
            assetAmounts_[1] = initiatorParams.withdrawAmount;
            vm.startPrank(users.accountOwner);
            account.openMarginAccount(address(lendingPoolMock));
            ERC721(address(positionManagerV4)).approve(address(account), positionId);
            token1.approve(address(account), initiatorParams.withdrawAmount);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        // And: Position has debt.
        debt = bound(debt, 1, 1e8);
        lendingPoolMock.setDebt(address(account), debt);

        // When: Calling close().
        vm.prank(initiator);
        closer.close(address(account), initiatorParams);

        // Then: Debt should be reduced or stay the same.
        assertLe(lendingPoolMock.debt(address(account)), debt);
    }
}
