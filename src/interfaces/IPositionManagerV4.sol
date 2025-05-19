// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import { PoolKey } from "../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";

interface IPositionManagerV4 {
    /// @notice Unlocks Uniswap v4 PoolManager and batches actions for modifying liquidity
    /// @dev This is the standard entrypoint for the PositionManager
    /// @param unlockData is an encoding of actions, and parameters for those actions
    /// @param deadline is the deadline for the batched actions to be executed
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;

    /// @notice Used to get the ID that will be used for the next minted liquidity position
    /// @return uint256 The next token ID
    function nextTokenId() external view returns (uint256);

    /// @notice Returns the pool key and position info of a position
    /// @param tokenId the ERC721 tokenId
    /// @return poolKey the pool key of the position
    /// @return PositionInfo a uint256 packed value holding information about the position including the range (tickLower, tickUpper)
    function getPoolAndPositionInfo(uint256 tokenId) external view returns (PoolKey memory, PositionInfo);

    function approve(address spender, uint256 tokenId) external;
}
