/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { ImmutableState } from "./ImmutableState.sol";
import { IStakedSlipstream } from "../interfaces/IStakedSlipstream.sol";

abstract contract StakedSlipstreamLogic is ImmutableState {
    function claimReward(address positionManager, uint256 id)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](1);
        amounts = new uint256[](1);
        tokens[0] = REWARD_TOKEN;
        amounts[0] = IStakedSlipstream(positionManager).claimReward(id);
    }
}
