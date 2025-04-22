/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

interface IStakedSlipstream {
    function claimReward(uint256 positionId) external returns (uint256 rewards);
}
