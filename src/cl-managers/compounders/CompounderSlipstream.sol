/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder } from "./Compounder.sol";
import { Slipstream } from "../base/Slipstream.sol";

/**
 * @title Compounder for Slipstream Liquidity Positions.
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
contract CompounderSlipstream is Compounder, Slipstream {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param owner_ The address of the Owner.
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param routerTrampoline The contract address of the Router Trampoline.
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
        address routerTrampoline,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    )
        Compounder(owner_, arcadiaFactory, routerTrampoline)
        Slipstream(positionManager, cLFactory, poolImplementation, rewardToken, stakedSlipstreamAm, stakedSlipstreamWrapper)
    { }
}
