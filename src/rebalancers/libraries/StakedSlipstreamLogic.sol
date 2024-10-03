/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";

library StakedSlipstreamLogic {
    address internal constant REWARD_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;

    // The Staked Slipstream Asset Module contract.
    IStakedSlipstreamAM internal constant POSITION_MANAGER =
        IStakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);
}
