/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Closer } from "../../../../../src/cl-managers/closers/Closer.sol";
import { CloserUniswapV4_Fuzz_Test } from "./_CloserUniswapV4.fuzz.t.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { Guardian } from "../../../../../src/guardian/Guardian.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";

/**
 * @notice Fuzz tests for the function "close" of contract "CloserUniswapV4".
 */
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
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity));
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

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

        // And: Configure initiator params - partial decrease only (not full burn).
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = uint128(bound(initiatorParams.liquidity, 0, position.liquidity - 1));
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

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

        // And: Configure initiator params - full burn (liquidity >= position.liquidity).
        initiatorParams.positionManager = address(positionManagerV4);
        initiatorParams.id = uint96(position.id);
        initiatorParams.liquidity = position.liquidity;
        initiatorParams.withdrawAmount = 0;
        initiatorParams.maxRepayAmount = 0;
        initiatorParams.claimFee = uint64(bound(initiatorParams.claimFee, 0, MAX_CLAIM_FEE));

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
}
