/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

import { PoolKey } from "../../../lib/accounts-v2/lib/v4-periphery/lib/v4-core/src/types/PoolKey.sol";
import { PositionInfo } from "../../../lib/accounts-v2/lib/v4-periphery/src/libraries/PositionInfoLibrary.sol";

interface IPositionManagerV4 {
    function modifyLiquidities(bytes calldata unlockData, uint256 deadline) external payable;
    function getPoolAndPositionInfo(uint256 tokenId) external view returns (PoolKey memory, PositionInfo);
}
