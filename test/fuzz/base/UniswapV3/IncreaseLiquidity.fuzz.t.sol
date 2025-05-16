/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { PositionState } from "../../../../src/state/PositionState.sol";
import { UniswapV3_Fuzz_Test } from "./_UniswapV3.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_increaseLiquidity" of contract "UniswapV3".
 */
contract IncreaseLiquidity_UniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_increaseLiquidity(
        uint128 liquidityPool,
        address positionManager,
        PositionState memory position,
        uint128 balance0,
        uint128 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position);
        givenValidPositionState(position);
        setPositionState(position);

        // Transfer position to base.
        vm.prank(users.liquidityProvider);
        ERC721(address(nonfungiblePositionManager)).transferFrom(users.liquidityProvider, address(base), position.id);

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPrice <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPrice <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPrice), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower), uint160(position.sqrtPrice), balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contract has sufficient balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling increaseLiquidity.
        PositionState memory position_;
        (balances, position_) = base.increaseLiquidity(balances, positionManager, position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(nonfungiblePositionManager)).ownerOf(position_.id), address(base));

        // And: Correct liquidity should be returned.
        {
            uint256 liquidity_ = LiquidityAmounts.getLiquidityForAmounts(
                uint160(position.sqrtPrice),
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0,
                balance1
            );
            assertEq(position_.liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }
}
