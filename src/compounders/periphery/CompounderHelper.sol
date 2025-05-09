/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { IFactory } from "../../interfaces/IFactory.sol";
import { SlipstreamLogic } from "../slipstream/libraries/SlipstreamLogic.sol";
import { SlipstreamCompounderHelperLogic } from "./libraries/slipstream/SlipstreamCompounderHelperLogic.sol";
import { SlipstreamLogic } from "../slipstream/libraries/SlipstreamLogic.sol";
import { UniswapV3Logic } from "../uniswap-v3/libraries/UniswapV3Logic.sol";
import { UniswapV4Logic } from "../uniswap-v4/libraries/UniswapV4Logic.sol";
import { UniswapV4CompounderHelper } from "./uniswap-v4/UniswapV4CompounderHelper.sol";
import { UniswapV3CompounderHelperLogic } from "./libraries/uniswap-v3/UniswapV3CompounderHelperLogic.sol";

/**
 * @title Off-chain view functions for Compounder Asset-Manager.
 * @author Pragma Labs
 * @notice This contract holds view functions accessible for initiators to check if the fees of a certain Liquidity Position can be compounded.
 */
contract CompounderHelper {
    /* //////////////////////////////////////////////////////////////
                               CONSTANTS
    ////////////////////////////////////////////////////////////// */

    IFactory internal immutable FACTORY;
    UniswapV4CompounderHelper internal immutable UNISWAPV4_COMPOUNDER_HELPER;

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address factory_, address uniswapV4CompounderHelper) {
        FACTORY = IFactory(factory_);
        UNISWAPV4_COMPOUNDER_HELPER = UniswapV4CompounderHelper(uniswapV4CompounderHelper);
    }

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @param positionManager The address of the nonfungiblePositionManager.
     * @param account The owner of the position, which should be an Arcadia Account.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @return compounder The address of the specific Compounder to call for the given asset.
     * @return sqrtPriceX96 The current sqrtPriceX96 of the pool.
     * @dev While this function does not persist state changes, it cannot be declared as view function.
     * Since quoteExactOutputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id, address positionManager, address account)
        external
        returns (bool isCompoundable_, address compounder, uint160 sqrtPriceX96)
    {
        bool isAccount = FACTORY.isAccount(account);
        if (!isAccount) return (false, address(0), 0);

        // As the position manager for UniswapV4 needs to be overwritten for tests,
        // we need to call the constant outside of "else if" statement.
        bool isUniswapV4 = positionManager == address(UniswapV4Logic.POSITION_MANAGER);

        if (positionManager == address(SlipstreamLogic.POSITION_MANAGER)) {
            (isCompoundable_, compounder, sqrtPriceX96) = SlipstreamCompounderHelperLogic._isCompoundable(id, account);
        } else if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
            (isCompoundable_, compounder, sqrtPriceX96) =
                UniswapV3CompounderHelperLogic._isCompoundable(id, positionManager, account);
        } else if (isUniswapV4) {
            (isCompoundable_, compounder, sqrtPriceX96) = UNISWAPV4_COMPOUNDER_HELPER.isCompoundable(id, account);
        }
    }
}
