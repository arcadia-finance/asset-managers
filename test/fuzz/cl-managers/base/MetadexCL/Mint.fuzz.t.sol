/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC721 } from "../../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LiquidityAmounts } from "../../../../../src/cl-managers/libraries/LiquidityAmounts.sol";
import { MetadexCL_Fuzz_Test } from "./_MetadexCL.fuzz.t.sol";
import { PositionState } from "../../../../../src/cl-managers/state/PositionState.sol";
import { TickMath } from "../../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "_mint" of contract "Slipstream", on Metadex CL.
 */
contract Mint_MetadexCL_Fuzz_Test is MetadexCL_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MetadexCL_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_mint(
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

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        uint128 maxLiquidity = tickSpacingToMaxLiquidityPerTick(TICK_SPACING);
        if (position.sqrtPrice <= TickMath.getSqrtPriceAtTick(position.tickLower)) {
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < maxLiquidity);
        } else if (position.sqrtPrice <= TickMath.getSqrtPriceAtTick(position.tickUpper)) {
            // forge-lint: disable-next-item(unsafe-typecast)
            uint256 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(
                uint160(position.sqrtPrice), TickMath.getSqrtPriceAtTick(position.tickUpper), balance0
            );
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            // forge-lint: disable-next-item(unsafe-typecast)
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                // forge-lint: disable-next-item(unsafe-typecast)
                TickMath.getSqrtPriceAtTick(position.tickLower),
                // forge-lint: disable-next-item(unsafe-typecast)
                uint160(position.sqrtPrice),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < maxLiquidity);
        } else {
            uint256 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(
                TickMath.getSqrtPriceAtTick(position.tickLower),
                TickMath.getSqrtPriceAtTick(position.tickUpper),
                balance1
            );
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < maxLiquidity);
        }

        // And: Contract has sufficient balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(base), balance0, true);
        deal(address(token1), address(base), balance1, true);

        // When: Calling mint.
        PositionState memory position_;
        (balances, position_) = base.mint(balances, positionManager, position, balance0, balance1);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(metadex03PositionManager)).ownerOf(position_.id), address(base));

        // And: Correct liquidity should be returned.
        {
            (,,,,,,, uint256 liquidity_,,,,) = metadex03PositionManager.positions(position_.id);
            assertEq(position_.liquidity, liquidity_);
        }

        // And: Correct balances should be returned.
        assertEq(balances[0], token0.balanceOf(address(base)));
        assertEq(balances[1], token1.balanceOf(address(base)));
    }
}
