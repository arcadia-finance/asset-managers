/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "./Compounder2.sol";
import { UniswapV3 } from "../base/UniswapV3.sol";

/**
 * @title Compounder for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Compounder will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the compounding functionality for a Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to compound the positions in their Account.
 * Compounding can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The compounding will collect the fees earned by a position and increase the liquidity of the position by those fees.
 * Depending on current tick of the pool and the position range, fees will be deposited in appropriate ratio.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of compounding to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the compounding process,
 * ensuring that the execution remains within a controlled price range.
 */
contract CompounderUniswapV3 is Compounder, UniswapV3 {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxTolerance The maximum allowed deviation of the actual pool price for any initiator,
     * relative to the price calculated with trusted external prices of both assets, with 18 decimals precision.
     * @param maxFee The maximum fee an initiator can set, with 18 decimals precision.
     * @param minLiquidityRatio The ratio of the minimum amount of liquidity that must be minted,
     * relative to the hypothetical amount of liquidity when we rebalance without slippage, with 18 decimals precision.
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxTolerance,
        uint256 maxFee,
        uint256 minLiquidityRatio,
        address positionManager,
        address uniswapV3Factory
    )
        Compounder(arcadiaFactory, maxTolerance, maxFee, minLiquidityRatio)
        UniswapV3(positionManager, uniswapV3Factory)
    { }
}
