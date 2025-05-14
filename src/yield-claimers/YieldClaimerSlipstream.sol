/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { AbstractBase } from "../base/AbstractBase.sol";
import { PositionState } from "../state/PositionState.sol";
import { Slipstream } from "../base/Slipstream.sol";
import { YieldClaimer } from "./YieldClaimer.sol";

/**
 * @title Yield Claimer for Slipstream Liquidity Positions.
 * @author Pragma Labs
 */
contract YieldClaimerSlipstream is YieldClaimer, Slipstream {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param arcadiaFactory The contract address of the Arcadia Factory.
     * @param maxClaimFee The maximum fee an initiator can set.
     * @param positionManager The contract address of the Slipstream Position Manager.
     * @param cLFactory The contract address of the Slipstream Factory.
     * @param poolImplementation The contract address of the Slipstream Pool Implementation.
     * @param rewardToken The contract address of the Reward Token (Aero).
     * @param stakedSlipstreamAm The contract address of the Staked Slipstream Asset Module.
     * @param stakedSlipstreamWrapper The contract address of the Staked Slipstream Wrapper.
     */
    constructor(
        address arcadiaFactory,
        uint256 maxClaimFee,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    )
        YieldClaimer(arcadiaFactory, maxClaimFee)
        Slipstream(positionManager, cLFactory, poolImplementation, rewardToken, stakedSlipstreamAm, stakedSlipstreamWrapper)
    { }

    /* ///////////////////////////////////////////////////////////////
                          STAKING LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Stakes a Liquidity Position.
     * param balances The balances of the underlying tokens held by the Rebalancer.
     * param positionManager The contract address of the Position Manager.
     * param position A struct with position and pool related variables.
     */
    function _stake(uint256[] memory, address, PositionState memory) internal override(AbstractBase, Slipstream) { }
}
