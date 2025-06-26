/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { UniswapV3 } from "../base/UniswapV3.sol";
import { YieldClaimer } from "./YieldClaimer.sol";

/**
 * @title Yield Claimer for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 */
contract YieldClaimerUniswapV3 is YieldClaimer, UniswapV3 {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(address arcadiaFactory, address positionManager, address uniswapV3Factory)
        YieldClaimer(arcadiaFactory)
        UniswapV3(positionManager, uniswapV3Factory)
    { }
}
