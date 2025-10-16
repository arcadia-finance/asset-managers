/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AbstractBase } from "../../../../../src/cl-managers/base/AbstractBase.sol";
import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { IWETH } from "../../../../../src/cl-managers/interfaces/IWETH.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_claim" of contract "UniswapV4".
 */
contract Claim_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_claim_NotNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint96 fee0,
        uint96 fee1,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // And: position has fees.
        generateFees(fee0, fee1);
        (uint256 fee0_, uint256 fee1_) = getFeeAmounts(position.id);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token0), fee0_);
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token1), fee1_);
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], uint256(balance0) + fee0_);
        assertEq(balances[1], uint256(balance1) + fee1_);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], fee0_ * claimFee / 1e18);
        assertEq(fees[1], fee1_ * claimFee / 1e18);
    }

    function testFuzz_Success_claim_IsNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint96 fee0,
        uint96 fee1,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: claimFee is below 100%.
        claimFee = uint64(bound(claimFee, 0, 1e18));

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(base), balance0);
        vm.prank(address(base));
        IWETH(address(weth9)).deposit{ value: balance0 }();
        deal(address(token1), address(base), balance1, true);

        // And: position has fees.
        generateFees(fee0, fee1);
        (uint256 fee0_, uint256 fee1_) = getFeeAmounts(position.id);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        vm.prank(address(account));
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(0), fee0_);
        vm.expectEmit();
        emit AbstractBase.YieldClaimed(address(account), address(token1), fee1_);
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], fee0_);
        assertEq(balances[1], uint256(balance1) + fee1_);
        assertEq(balances[0], address(base).balance);
        assertEq(balances[1], token1.balanceOf(address(base)));

        // balance0 is in weth and should not be taken into account for native eth!!!
        assertEq(balance0, weth9.balanceOf(address(base)));

        assertEq(fees[0], fee0_ * claimFee / 1e18);
        assertEq(fees[1], fee1_ * claimFee / 1e18);
    }
}
