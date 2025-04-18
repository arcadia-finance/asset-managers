// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

/// @title Non-fungible token for positions
/// @notice Wraps Slipstream positions in a non-fungible token interface which allows for them to be transferred
/// and authorized.

struct CollectParams {
    uint256 tokenId;
    address recipient;
    uint128 amount0Max;
    uint128 amount1Max;
}

interface ISlipstreamPositionManager {
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}
