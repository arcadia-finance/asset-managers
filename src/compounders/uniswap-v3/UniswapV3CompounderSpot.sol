/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaLogic } from "../libraries/ArcadiaLogic.sol";
import { FixedPointMathLib } from "../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { TickMath } from "../../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";
import { UniswapV3Compounder } from "./UniswapV3Compounder.sol";
import { UniswapV3Logic } from "./libraries/UniswapV3Logic.sol";
import { TwapLogic } from "../../libraries/TwapLogic.sol";

/**
 * @title Permissionless and Stateless Compounder for UniswapV3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the compounding functionality for a Uniswap V3 Liquidity Position in the Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The contract prevents frontrunning/sandwiching by comparing the actual pool price with a pool price calculated from a TWAP.
 */
contract UniswapV3CompounderSpot is UniswapV3Compounder {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param initiatorShare The share of the fees paid to the initiator as reward, with 18 decimals precision.
     * @param tolerance The maximum deviation of the actual pool price,
     * relative to the price calculated with the TWAP, with 18 decimals precision.
     * @dev The tolerance for the pool price will be converted to an upper and lower max sqrtPrice deviation,
     * using the square root of the basis (one with 18 decimals precision) +- tolerance (18 decimals precision).
     * The tolerance boundaries are symmetric around the price, but taking the square root will result in a different
     * allowed deviation of the sqrtPriceX96 for the lower and upper boundaries.
     */
    constructor(uint256, uint256 initiatorShare, uint256 tolerance) UniswapV3Compounder(0, initiatorShare, tolerance) { }

    /* ///////////////////////////////////////////////////////////////
                    POSITION AND POOL VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Fetches all required position data from external contracts.
     * @param id The id of the Liquidity Position.
     * @return position Struct with the position data.
     */
    function getPositionState(uint256 id) public view override returns (PositionState memory position) {
        // Get data of the Liquidity Position.
        int24 tickLower;
        int24 tickUpper;
        (,, position.token0, position.token1, position.fee, tickLower, tickUpper,,,,,) =
            UniswapV3Logic.POSITION_MANAGER.positions(id);
        position.sqrtRatioLower = TickMath.getSqrtRatioAtTick(tickLower);
        position.sqrtRatioUpper = TickMath.getSqrtRatioAtTick(tickUpper);

        // Get data of the Liquidity Pool.
        position.pool = UniswapV3Logic._computePoolAddress(position.token0, position.token1, position.fee);
        (position.sqrtPriceX96,,,,,,) = IUniswapV3Pool(position.pool).slot0();

        // Calculate the time weighted average tick over 300s.
        // It is used only to ensure that the deposited Liquidity range and thus
        // the risk of exposure manipulation is acceptable.
        int24 twat = TwapLogic._getTwat(position.pool);
        // Get the time weighted average sqrtPriceX96 over 300s.
        uint256 twaSqrtRatioX96 = TickMath.getSqrtRatioAtTick(twat);

        // Calculate the upper and lower bounds of sqrtPriceX96 for the Pool to be balanced.
        position.lowerBoundSqrtPriceX96 = twaSqrtRatioX96.mulDivDown(LOWER_SQRT_PRICE_DEVIATION, 1e18);
        position.upperBoundSqrtPriceX96 = twaSqrtRatioX96.mulDivDown(UPPER_SQRT_PRICE_DEVIATION, 1e18);
    }

    /**
     * @notice We don't make use of a minimum threshold for Spot Accounts,
     * as we don't rely on third party oracles for USD prices but on a TWAP.
     */
    function isBelowThreshold(PositionState memory, Fees memory) public pure override returns (bool) {
        return false;
    }
}
