/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { ISlipstreamPositionManager } from "../interfaces/ISlipstreamPositionManager.sol";

library SlipstreamLogic {
    // The Slipstream NonfungiblePositionManager contract.
    ISlipstreamPositionManager internal constant POSITION_MANAGER =
        ISlipstreamPositionManager(0x827922686190790b37229fd06084350E74485b72);
}
