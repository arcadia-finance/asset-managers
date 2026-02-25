/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer } from "./Closer.sol";
import { Slipstream } from "../base/Slipstream.sol";

/**
 * @title Closer for Slipstream Liquidity Positions.
 * @author Pragma Labs
 * @notice The Closer will act as an Asset Manager for Arcadia Accounts.
 * It will allow third parties (initiators) to trigger the closing functionality for a Liquidity Position in the Account.
 * The Arcadia Account owner must set a specific initiator that will be permissioned to close the positions in their Account.
 * Closing can only be triggered if certain conditions are met and the initiator will get a small fee for the service provided.
 * The closing will collect the fees earned by a position and decrease or fully burn the liquidity of the position.
 * It can also repay debt to the lending pool if needed.
 */
contract CloserSlipstream is Closer, Slipstream {
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
     * @param positionManager The contract address of the Slipstream Position Manager.
     * @param cLFactory The contract address of the Slipstream Factory.
     * @param poolImplementation The contract address of the Slipstream Pool Implementation.
     * @param rewardToken The contract address of the Reward Token (Aero).
     * @param stakedSlipstreamAm The contract address of the Staked Slipstream Asset Module.
     * @param stakedSlipstreamWrapper The contract address of the Staked Slipstream Wrapper.
     */
    constructor(
        address owner_,
        address arcadiaFactory,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    )
        Closer(owner_, arcadiaFactory)
        Slipstream(
            positionManager, cLFactory, poolImplementation, rewardToken, stakedSlipstreamAm, stakedSlipstreamWrapper
        )
    { }
}
