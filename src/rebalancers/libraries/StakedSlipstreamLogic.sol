/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

import { IStakedSlipstreamAM } from "../interfaces/IStakedSlipstreamAM.sol";
import { Rebalancer } from "../Rebalancer.sol";

library StakedSlipstreamLogic {
    // The Slipstream NonfungiblePositionManager contract.
    IStakedSlipstreamAM internal constant POSITION_MANAGER =
        IStakedSlipstreamAM(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1);

    function _getPositionState(Rebalancer.PositionState memory position) internal view {
        address rewardToken = POSITION_MANAGER.REWARD_TOKEN();
        if (rewardToken != position.token0 && rewardToken != position.token1) position.tokenR = rewardToken;
    }
}
