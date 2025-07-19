/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Rebalancer } from "./Rebalancer.sol";
import { Slipstream } from "../base/Slipstream.sol";

/**
 * @title Rebalancer for Slipstream Liquidity Positions.
 * @notice The Rebalancer is an Asset Manager for Arcadia Accounts.
 * It will allow third parties to trigger the rebalancing functionality for a Liquidity Position in the Account.
 * The owner of an Arcadia Account should set an initiator via setAccountInfo() that will be permissioned to rebalance
 * all Liquidity Positions held in that Account.
 * @dev The initiator will provide a trusted sqrtPrice input at the time of rebalance to mitigate frontrunning risks.
 * This input serves as a reference point for calculating the maximum allowed deviation during the rebalancing process,
 * ensuring that rebalancing remains within a controlled price range.
 * @dev The contract guarantees a limited slippage with each rebalance by enforcing a minimum amount of liquidity that must be added,
 * based on a hypothetical optimal swap through the pool itself without slippage.
 * This protects the Account owners from incompetent or malicious initiators who route swaps poorly, or try to skim off liquidity from the position.
 */
contract RebalancerSlipstream is Rebalancer, Slipstream {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
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
        address arcadiaFactory,
        address routerTrampoline,
        address positionManager,
        address cLFactory,
        address poolImplementation,
        address rewardToken,
        address stakedSlipstreamAm,
        address stakedSlipstreamWrapper
    )
        Rebalancer(arcadiaFactory, routerTrampoline)
        Slipstream(positionManager, cLFactory, poolImplementation, rewardToken, stakedSlipstreamAm, stakedSlipstreamWrapper)
    { }
}
