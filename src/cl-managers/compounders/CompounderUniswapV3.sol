/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Compounder } from "./Compounder.sol";
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
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The version of the Asset Manager.
    string public constant VERSION = "2.1.0";

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param routerTrampoline The contract address of the Router Trampoline.
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(
        address owner_,
        address arcadiaFactory,
        address routerTrampoline,
        address positionManager,
        address uniswapV3Factory
    ) Compounder(owner_, arcadiaFactory, routerTrampoline) UniswapV3(positionManager, uniswapV3Factory) { }
}
