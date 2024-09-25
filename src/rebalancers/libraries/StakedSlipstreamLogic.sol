/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";
import { Rebalancer } from "../Rebalancer.sol";

library StakedSlipstreamLogic {
    // The Staked Slipstream Asset Module contract.
    IStakedSlipstreamAM internal constant POSITION_MANAGER =
        IStakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);

    /**
     * @notice Fetches Staked Slipstream specific position data from external contracts.
     * @param position Struct with the position data.
     */
    function _getPositionState(Rebalancer.PositionState memory position) internal view {
        address rewardToken = POSITION_MANAGER.REWARD_TOKEN();
        if (rewardToken != position.token0 && rewardToken != position.token1) position.tokenR = rewardToken;
    }
}
