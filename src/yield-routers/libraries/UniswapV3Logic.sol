/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { IPositionManagerV3 } from "../interfaces/IPositionManagerV3.sol";

library UniswapV3Logic {
    // The Uniswap V3 NonfungiblePositionManager contract.
    IPositionManagerV3 internal constant POSITION_MANAGER =
        IPositionManagerV3(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
}
