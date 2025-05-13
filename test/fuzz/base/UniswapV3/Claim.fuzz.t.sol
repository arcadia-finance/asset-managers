/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_claim" of contract "UniswapV3".
 */
contract Claim_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_claim(
        uint128 liquidityPool,
        PositionState memory position,
        uint64 balance0,
        uint64 balance1,
        uint80 swap0,
        uint80 swap1,
        uint64 claimFee
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
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
        generateFees(swap0, swap1);
        (uint256 fee0, uint256 fee1) = getFeeAmounts(position.id);

        // And: Transfer position to Base.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // When: Calling claim.
        uint256[] memory fees = new uint256[](2);
        (balances, fees) = base.claim(balances, fees, address(nonfungiblePositionManager), position, claimFee);

        // Then: It should return the correct balances.
        assertEq(balances[0], uint256(balance0) + fee0);
        assertEq(balances[1], uint256(balance1) + fee1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(fees[0], fee0 * claimFee / 1e18);
        assertEq(fees[1], fee1 * claimFee / 1e18);
    }
}
