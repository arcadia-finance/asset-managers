/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
}

interface ISlipstreamPositionManager {
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}
