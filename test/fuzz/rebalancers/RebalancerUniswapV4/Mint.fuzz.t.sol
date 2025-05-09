/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { LiquidityAmounts } from "../../../../src/libraries/LiquidityAmounts.sol";
import { Rebalancer, RebalanceParams } from "../../../../src/rebalancers/Rebalancer.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { SqrtPriceMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/SqrtPriceMath.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_mint" of contract "RebalancerUniswapV4".
 */
contract Mint_RebalancerUniswapV4_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_mint_NotNative(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, false);
        givenValidPositionState(position);

        cache.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        cache.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPrice <= cache.sqrtRatioLower) {
            uint256 liquidity0 =
                LiquidityAmounts.getLiquidityForAmount0(cache.sqrtRatioLower, cache.sqrtRatioUpper, balance0);
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPrice <= cache.sqrtRatioUpper) {
            uint256 liquidity0 =
                LiquidityAmounts.getLiquidityForAmount0(uint160(position.sqrtPrice), cache.sqrtRatioUpper, balance0);
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 =
                LiquidityAmounts.getLiquidityForAmount1(cache.sqrtRatioLower, uint160(position.sqrtPrice), balance1);
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 =
                LiquidityAmounts.getLiquidityForAmount1(cache.sqrtRatioLower, cache.sqrtRatioUpper, balance1);
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contract has sufficient balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        deal(address(token0), address(rebalancer), balance0, true);
        deal(address(token1), address(rebalancer), balance1, true);

        // When: Calling mint.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.mint(balances, initiatorParams, position, cache);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position_.id), address(rebalancer));

        // And: Correct liquidity should be returned.
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(position_.id))
        );
        assertEq(position_.liquidity, stateView.getPositionLiquidity(poolKey.toId(), positionId));

        // And: Correct balances should be returned.
        assertEq(balances[0], token0.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));
    }

    function testFuzz_Success_mint_IsNative(
        uint128 liquidityPool,
        Rebalancer.InitiatorParams memory initiatorParams,
        Rebalancer.PositionState memory position,
        Rebalancer.Cache memory cache,
        uint128 balance0,
        uint128 balance1
    ) public {
        // Given: A valid position.
        liquidityPool = givenValidPoolState(liquidityPool, position);
        setPoolState(liquidityPool, position, true);
        givenValidPositionState(position);

        cache.sqrtRatioLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        cache.sqrtRatioUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);

        // And: Liquidity is not 0, does not overflow and is below max liquidity.
        if (position.sqrtPrice <= cache.sqrtRatioLower) {
            uint256 liquidity0 =
                LiquidityAmounts.getLiquidityForAmount0(cache.sqrtRatioLower, cache.sqrtRatioUpper, balance0);
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < UniswapHelpers.maxLiquidity(1));
        } else if (position.sqrtPrice <= cache.sqrtRatioUpper) {
            uint256 liquidity0 =
                LiquidityAmounts.getLiquidityForAmount0(uint160(position.sqrtPrice), cache.sqrtRatioUpper, balance0);
            vm.assume(liquidity0 > 0);
            vm.assume(liquidity0 < type(uint128).max);
            uint256 liquidity1 =
                LiquidityAmounts.getLiquidityForAmount1(cache.sqrtRatioLower, uint160(position.sqrtPrice), balance1);
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < type(uint128).max);
            vm.assume((liquidity0 < liquidity1 ? liquidity0 : liquidity1) < UniswapHelpers.maxLiquidity(1));
        } else {
            uint256 liquidity1 =
                LiquidityAmounts.getLiquidityForAmount1(cache.sqrtRatioLower, cache.sqrtRatioUpper, balance1);
            vm.assume(liquidity1 > 0);
            vm.assume(liquidity1 < UniswapHelpers.maxLiquidity(1));
        }

        // And: Contract has sufficient balances.
        uint256[] memory balances = new uint256[](2);
        balances[0] = balance0;
        balances[1] = balance1;
        vm.deal(address(rebalancer), balance0);
        deal(address(token1), address(rebalancer), balance1, true);

        // When: Calling mint.
        Rebalancer.PositionState memory position_;
        (balances, position_) = rebalancer.mint(balances, initiatorParams, position, cache);

        // Then: Contract is owner of the position.
        assertEq(ERC721(address(positionManagerV4)).ownerOf(position_.id), address(rebalancer));

        // And: Correct liquidity should be returned.
        bytes32 positionId = keccak256(
            abi.encodePacked(address(positionManagerV4), position.tickLower, position.tickUpper, bytes32(position_.id))
        );
        assertEq(position_.liquidity, stateView.getPositionLiquidity(poolKey.toId(), positionId));

        // And: Correct balances should be returned.
        assertEq(balances[0], weth9.balanceOf(address(rebalancer)));
        assertEq(balances[1], token1.balanceOf(address(rebalancer)));

        // And: token0 is weth.
        assertEq(position_.tokens[0], address(weth9));
    }
}
