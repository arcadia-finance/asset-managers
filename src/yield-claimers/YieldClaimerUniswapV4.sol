/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { UniswapV4 } from "../base/UniswapV4.sol";
import { YieldClaimer } from "./YieldClaimer.sol";

/**
 * @title Yield Claimer for Uniswap V4 Liquidity Positions.
 * @author Pragma Labs
 */
contract YieldClaimerUniswapV4 is YieldClaimer, UniswapV4 {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxClaimFee The maximum fee an initiator can set.
     * @param positionManager The contract address of the Uniswap v4 Position Manager.
     * @param permit2 The contract address of Permit2.
     * @param poolManager The contract address of the Uniswap v4 Pool Manager.
     * @param weth The contract address of WETH.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxClaimFee,
        address positionManager,
        address permit2,
        address poolManager,
        address weth
    ) YieldClaimer(arcadiaFactory, maxClaimFee) UniswapV4(positionManager, permit2, poolManager, weth) { }
}
