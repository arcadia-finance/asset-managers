/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ERC20, ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC721 } from "../../../../lib/accounts-v2/lib/solmate/src/tokens/ERC721.sol";
import { FixedPoint128 } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "../../../../src/rebalancers/libraries/cl-math/LiquidityAmounts.sol";
import { RebalancerUniswapV4 } from "../../../../src/rebalancers/RebalancerUniswapV4.sol";
import { RebalancerUniswapV4_Fuzz_Test } from "./_RebalancerUniswapV4.fuzz.t.sol";
import { TickMath } from "../../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/libraries/TickMath.sol";
import { UniswapHelpers } from "../../../utils/uniswap-v3/UniswapHelpers.sol";

/**
 * @notice Fuzz tests for the function "_burn" of contract "RebalancerUniswapV4".
 */
contract Burn_BurnLogic_Fuzz_Test is RebalancerUniswapV4_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(RebalancerUniswapV4_Fuzz_Test) {
        RebalancerUniswapV4_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_burn(InitVariables memory initVars, LpVariables memory lpVars, FeeGrowth memory feeData)
        public
    {
        // Given: A valid position.
        uint256 id;
        (initVars, lpVars, id) = initPoolAndCreatePositionWithFees(initVars, lpVars, feeData);

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), lpVars.tickLower, lpVars.tickUpper, bytes32(id)));
        lpVars.liquidity = stateView.getPositionLiquidity(v4PoolKey.toId(), positionId);

        // And: Position has accumulated fees.
        (uint256 feeAmount0, uint256 feeAmount1) =
            getFeeAmounts(id, v4PoolKey.toId(), lpVars.tickLower, lpVars.tickUpper, lpVars.liquidity);
        vm.assume(feeAmount0 + feeAmount1 > 0);

        (uint160 sqrtPriceX96,,,) = stateView.getSlot0(v4PoolKey.toId());
        (uint256 principal0, uint256 principal1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lpVars.tickLower),
            TickMath.getSqrtPriceAtTick(lpVars.tickUpper),
            lpVars.liquidity
        );

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1) = rebalancer.burn(id, address(token0), address(token1));

        // Then: Correct balances should be returned.
        assertEq(balance0, principal0 + feeAmount0);
        assertEq(balance1, principal1 + feeAmount1);

        // And: Correct balances are transferred.
        assertEq(token0.balanceOf(address(rebalancer)), balance0);
        assertEq(token1.balanceOf(address(rebalancer)), balance1);
    }

    function testFuzz_Success_burn_nativeETH(uint128 liquidity) public {
        // Given: A valid position.
        liquidity = uint128(bound(liquidity, 1, UniswapHelpers.maxLiquidity(1)));
        (uint256 id, uint256 sqrtPriceX96) = deployNativeEthPool(liquidity, POOL_FEE, TICK_SPACING, address(0));

        bytes32 positionId =
            keccak256(abi.encodePacked(address(positionManagerV4), BOUND_TICK_LOWER, BOUND_TICK_UPPER, bytes32(id)));
        liquidity = stateView.getPositionLiquidity(nativeEthPoolKey.toId(), positionId);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            uint160(sqrtPriceX96),
            TickMath.getSqrtPriceAtTick(BOUND_TICK_LOWER),
            TickMath.getSqrtPriceAtTick(BOUND_TICK_UPPER),
            liquidity
        );

        // Transfer position to contract.
        vm.prank(users.liquidityProvider);
        ERC721(address(positionManagerV4)).transferFrom(users.liquidityProvider, address(rebalancer), id);

        // When: Calling _burn().
        (uint256 balance0, uint256 balance1) = rebalancer.burn(id, address(0), address(token1));

        // Then: Correct balances should be returned.
        assertEq(balance0, amount0);
        assertEq(balance1, amount1);

        // And: Correct balances are transferred.
        assertEq(address(rebalancer).balance, balance0);
        assertEq(token1.balanceOf(address(rebalancer)), balance1);
    }
}
