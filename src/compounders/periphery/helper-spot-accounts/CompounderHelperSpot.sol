/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AlienBaseLogic } from "../../alien-base/libraries/AlienBaseLogic.sol";
import { SlipstreamCompounderHelperLogic } from "../libraries/SlipstreamCompounderHelperLogic.sol";
import { SlipstreamLogic } from "../../slipstream/libraries/SlipstreamLogic.sol";
import { UniswapV3CompounderHelperLogic } from "../libraries/UniswapV3CompounderHelperLogic.sol";
import { UniswapV3Logic } from "../../uniswap-v3/libraries/UniswapV3Logic.sol";

/**
 * @title Off-chain view functions for Compounder Asset-Manager for Spot Accounts.
 * @author Pragma Labs
 * @notice This contract holds view functions accessible for initiators to check if the fees of a certain Liquidity Position can be compounded for Spot Accounts.
 */
contract CompounderHelperSpot {
    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor() { }

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @param positionManager The address of the nonfungiblePositionManager.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @dev While this function does not persist state changes, it cannot be declared as view function.
     * Since quoteExactOutputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id, address positionManager) external returns (bool isCompoundable_) {
        if (positionManager == address(SlipstreamLogic.POSITION_MANAGER)) {
            isCompoundable_ = SlipstreamCompounderHelperLogic._isCompoundable(id);
        } else if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
            // isCompoundable takes a protocol id as second input, 0 = UniswapV3, 1 = AlienBase.
            isCompoundable_ = UniswapV3CompounderHelperLogic._isCompoundable(id, 0);
        } else if (positionManager == address(AlienBaseLogic.POSITION_MANAGER)) {
            // isCompoundable takes a protocol id as second input, 0 = UniswapV3, 1 = AlienBase.
            isCompoundable_ = UniswapV3CompounderHelperLogic._isCompoundable(id, 1);
        }
    }
}
