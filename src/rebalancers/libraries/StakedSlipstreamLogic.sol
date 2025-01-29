/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

library StakedSlipstreamLogic {
    // The contract address of the Reward Token (Aero).
    address internal constant REWARD_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // The Staked Slipstream Asset Module contract.
    address internal constant POSITION_MANAGER = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;

    // The Wrapped Staked Slipstream Asset Module contract.
    address internal constant POSITION_MANAGER_WRAPPED = address(0x00);
}
