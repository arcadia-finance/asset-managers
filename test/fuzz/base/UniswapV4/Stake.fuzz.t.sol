/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { UniswapV4_Fuzz_Test } from "./_UniswapV4.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_stake" of contract "UniswapV4".
 */
contract Stake_UniswapV4_Fuzz_Test is UniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_stake_NotNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1
    ) public {
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

        // When: Calling stake.
        PositionState memory position_;
        (balances, position_) = base.stake(balances, positionManager, position);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position_.id), address(base));

        // And: Correct balances should be returned.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }

    function testFuzz_Success_stake_IsNative(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1
    ) public {
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

        // When: Calling stake.
        PositionState memory position_;
        (balances, position_) = base.stake(balances, positionManager, position);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position_.id), address(base));

        // And: Correct balances should be returned.
        assertEq(balances[0], balance0);
        assertEq(balances[1], balance1);
        assertEq(balances[0], weth9.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));

        assertEq(0, address(base).balance);

        // And: token0 is weth.
        assertEq(position_.tokens[0], address(weth9));
    }
}
