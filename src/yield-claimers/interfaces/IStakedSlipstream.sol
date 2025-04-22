/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

interface IStakedSlipstream {
    function approve(address account, uint256 id) external;
    function claimReward(uint256 positionId) external returns (uint256 rewards);
    function REWARD_TOKEN() external view returns (address rewardToken);
}
