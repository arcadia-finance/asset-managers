/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

interface IStakedSlipstreamAM {
    function burn(uint256 id) external returns (uint256 rewards);

    function mint(uint256 id) external returns (uint256 id_);

    function REWARD_TOKEN() external view returns (address rewardToken);
}
