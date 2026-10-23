/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer } from "./Closer.sol";
import { UniswapV3 } from "../base/UniswapV3.sol";

/**
 * @title Closer for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The Closer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the closing functionality for a Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to close the positions in their Account.
 * Closing can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The closing will collect the fees earned by a position and decrease or fully burn the liquidity of the position.
 * It can also repay debt to the lending pool if needed.
 */
contract CloserUniswapV3 is Closer, UniswapV3 {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The version of the Asset Manager.
    string public constant VERSION = "1.0.0";

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param positionManager The contract address of the Uniswap v3 Position Manager.
     * @param uniswapV3Factory The contract address of the Uniswap v3 Factory.
     */
    constructor(address owner_, address arcadiaFactory, address positionManager, address uniswapV3Factory)
        Closer(owner_, arcadiaFactory)
        UniswapV3(positionManager, uniswapV3Factory)
    { }
}
