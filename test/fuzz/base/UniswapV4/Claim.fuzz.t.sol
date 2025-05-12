/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
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
        uint64 balance1
    ) public {
        uint256 claimFee = 0;
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_claim_IsNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1
    ) public {
        uint256 claimFee = 0;
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);
        setPositionState(position);

        // And: Base has balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(base), balance0);
        deal(address(token1), address(base), balance1, true);

        // Transfer position to Base.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, positionManager, position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], address(base).balance);
        assertEq(balances[1], token1.balanceOf(address(base)));
    }
}
