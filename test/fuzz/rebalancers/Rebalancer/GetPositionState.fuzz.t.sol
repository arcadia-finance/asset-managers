/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../../../../src/rebalancers/libraries/ArcadiaLogic.sol";
import { AssetValueAndRiskFactors } from "../../../../lib/accounts-v2/src/Registry.sol";
import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { PricingLogic } from "../../../../src/rebalancers/libraries/PricingLogic.sol";
import { TickMath } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { Rebalancer } from "../../../../src/rebalancers/Rebalancer.sol";
import { Rebalancer_Fuzz_Test } from "./_Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getPositionState" of contract "Rebalancer".
 */
contract GetPositionState_Rebalancer_Fuzz_Test is Rebalancer_Fuzz_Test {
    using FixedPointMathLib for uint256;
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_getPositionState_sameTickRange(InitVariables memory initVars, LpVariables memory lpVars)
        public
    {
        // Given : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // When : Calling getPositionState()
        Rebalancer.PositionState memory position =
            rebalancer.getPositionState(address(nonfungiblePositionManager), tokenId, 0, 0, initVars.initiator);

        // Then : It should return the correct values
        assertEq(position.token0, address(token0));
        assertEq(position.token1, address(token1));
        assertEq(position.fee, POOL_FEE);
        assertEq(position.pool, address(uniV3Pool));

        // Here we use approxEqRel as the difference between the LiquidityAmounts lib
        // and the effective deposit of liquidity can have a small diff (we check to max 0,01% diff)
        assertApproxEqRel(position.liquidity, lpVars.liquidity, 1e14);

        (uint160 sqrtPriceX96, int24 tickCurrent,,,,,) = uniV3Pool.slot0();

        int24 halfRangeTicks;
        {
            int24 tickSpacing = uniV3Pool.tickSpacing();
            halfRangeTicks = ((lpVars.tickUpper - lpVars.tickLower) / tickSpacing) / 2;
            halfRangeTicks *= tickSpacing;
        }
        int24 tickUpper = tickCurrent + halfRangeTicks;
        int24 tickLower = tickCurrent - halfRangeTicks;
        assertEq(position.tickUpper, tickUpper);
        assertEq(position.tickLower, tickLower);

        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        uint256 usdPriceToken0;
        uint256 usdPriceToken1;
        {
            address[] memory assets = new address[](2);
            assets[0] = address(token0);
            assets[1] = address(token1);
            uint256[] memory assetAmounts = new uint256[](2);
            assetAmounts[0] = 1e18;
            assetAmounts[1] = 1e18;

            AssetValueAndRiskFactors[] memory valuesAndRiskFactors =
                registry.getValuesInUsd(address(0), assets, new uint256[](2), assetAmounts);

            (usdPriceToken0, usdPriceToken1) = (valuesAndRiskFactors[0].assetValue, valuesAndRiskFactors[1].assetValue);
        }

        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
            rebalancer.initiatorInfo(initVars.initiator);

        uint256 lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(lowerSqrtPriceDeviation, 1e18);
        uint256 upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(upperSqrtPriceDeviation, 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96);
    }

    function testFuzz_Success_getPositionState_newTickRange(
        InitVariables memory initVars,
        LpVariables memory lpVars,
        int24 tickLower,
        int24 tickUpper
    ) public {
        // Given : tickLower and tickUpper are not both equal to zero
        tickLower = int24(bound(tickLower, TickMath.MIN_TICK, TickMath.MAX_TICK));
        tickUpper = int24(bound(tickUpper, TickMath.MIN_TICK, TickMath.MAX_TICK));
        vm.assume((tickLower != tickUpper));

        // And : Rebalancer is deployed
        deployRebalancer(MAX_TOLERANCE, MAX_INITIATOR_FEE);

        // And : Initialize a uniswapV3 pool and a lp position with valid test variables. Also generate fees for that position.
        uint256 tokenId;
        (initVars, lpVars, tokenId) = initPoolAndCreatePositionWithFees(initVars, lpVars);

        // When : Calling getPositionState()
        Rebalancer.PositionState memory position = rebalancer.getPositionState(
            address(nonfungiblePositionManager), tokenId, tickLower, tickUpper, initVars.initiator
        );

        // Then : It should return the correct values
        assertEq(position.token0, address(token0));
        assertEq(position.token1, address(token1));
        assertEq(position.fee, POOL_FEE);
        assertEq(position.pool, address(uniV3Pool));

        // Here we use approxEqRel as the difference between the LiquidityAmounts lib
        // and the effective deposit of liquidity can have a small diff (we check to max 0,01% diff)
        assertApproxEqRel(position.liquidity, lpVars.liquidity, 1e14);

        (uint160 sqrtPriceX96,,,,,,) = uniV3Pool.slot0();

        assertEq(position.tickUpper, tickUpper);
        assertEq(position.tickLower, tickLower);

        assertEq(position.sqrtPriceX96, sqrtPriceX96);

        uint256 usdPriceToken0;
        uint256 usdPriceToken1;
        {
            address[] memory assets = new address[](2);
            assets[0] = address(token0);
            assets[1] = address(token1);
            uint256[] memory assetAmounts = new uint256[](2);
            assetAmounts[0] = 1e18;
            assetAmounts[1] = 1e18;

            AssetValueAndRiskFactors[] memory valuesAndRiskFactors =
                registry.getValuesInUsd(address(0), assets, new uint256[](2), assetAmounts);

            (usdPriceToken0, usdPriceToken1) = (valuesAndRiskFactors[0].assetValue, valuesAndRiskFactors[1].assetValue);
        }

        uint256 trustedSqrtPriceX96 = PricingLogic._getSqrtPriceX96(usdPriceToken0, usdPriceToken1);

        (uint256 upperSqrtPriceDeviation, uint256 lowerSqrtPriceDeviation,,) =
            rebalancer.initiatorInfo(initVars.initiator);

        uint256 lowerBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(lowerSqrtPriceDeviation, 1e18);
        uint256 upperBoundSqrtPriceX96 = trustedSqrtPriceX96.mulDivDown(upperSqrtPriceDeviation, 1e18);

        assertEq(position.lowerBoundSqrtPriceX96, lowerBoundSqrtPriceX96);
        assertEq(position.upperBoundSqrtPriceX96, upperBoundSqrtPriceX96);
    }
}