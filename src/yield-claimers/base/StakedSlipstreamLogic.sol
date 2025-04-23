/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ImmutableState } from "./ImmutableState.sol";
import { IStakedSlipstream } from "../interfaces/IStakedSlipstream.sol";

abstract contract StakedSlipstreamLogic is ImmutableState {
    /**
     * @notice Claims reward tokens from a Staked Slipstream position.
     * @param positionManager The contract address of the Staked Slipstream Position Manager.
     * @param id The id of the Staked Slipstream Position.
     * @return tokens The address of the reward token (AERO).
     * @return amounts The amount of reward tokens claimed.
     */
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
