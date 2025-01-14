/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { AlienBaseLogic } from "../alien-base/libraries/AlienBaseLogic.sol";
import { IAccount } from "../../interfaces/IAccount.sol";
import { IFactory } from "../../interfaces/IFactory.sol";
import { SlipstreamLogic } from "../slipstream/libraries/SlipstreamLogic.sol";
import { SlipstreamMarginHelperLogic } from "./libraries/margin-accounts/slipstream/SlipstreamMarginHelperLogic.sol";
import { SlipstreamSpotHelperLogic } from "./libraries/spot-accounts/slipstream/SlipstreamSpotHelperLogic.sol";
import { SlipstreamLogic } from "../slipstream/libraries/SlipstreamLogic.sol";
import { UniswapV3Logic } from "../uniswap-v3/libraries/UniswapV3Logic.sol";
import { UniswapV3MarginHelperLogic } from "./libraries/margin-accounts/uniswap-v3/UniswapV3MarginHelperLogic.sol";
import { UniswapV3SpotHelperLogic } from "./libraries/spot-accounts/uniswap-v3/UniswapV3SpotHelperLogic.sol";

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

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    struct SpotAccountInfo {
        address token0;
        address token1;
        uint256 feeAmount0;
        uint256 feeAmount1;
    }

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(address factory_) {
        FACTORY = IFactory(factory_);
    }

    /* ///////////////////////////////////////////////////////////////
                      OFF-CHAIN VIEW FUNCTIONS
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Off-chain view function to check if the fees of a certain Liquidity Position can be compounded.
     * @param id The id of the Liquidity Position.
     * @param positionManager The address of the nonfungiblePositionManager.
     * @return isCompoundable_ Bool indicating if the fees can be compounded.
     * @return usdValueFees The total value of the fees in USD, with 18 decimals precision. Will return 0 for Spot Accounts.
     * @return accountInfo The info needed from a Spot Account to be able to price the fees.
     * @return compounder The address of the specific Compounder to call for the given asset.
     * @dev While this function does not persist state changes, it cannot be declared as view function.
     * Since quoteExactOutputSingle() of Uniswap's Quoter02.sol uses a try - except pattern where it first
     * does the swap (with state changes), next it reverts (state changes are not persisted) and information about
     * the final state is passed via the error message in the expect.
     */
    function isCompoundable(uint256 id, address positionManager, address owner)
        external
        returns (bool isCompoundable_, uint256 usdValueFees, SpotAccountInfo memory accountInfo, address compounder)
    {
        bool isAccount = FACTORY.isAccount(owner);
        if (!isAccount) return (false, 0, accountInfo, address(0));

        bool isSpotAccount = IAccount(owner).ACCOUNT_VERSION() == 2 ? true : false;

        if (isSpotAccount) {
            if (positionManager == address(SlipstreamLogic.POSITION_MANAGER)) {
                (isCompoundable_, accountInfo, compounder) = SlipstreamSpotHelperLogic.isCompoundable(id);
            } else if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
                (isCompoundable_, accountInfo, compounder) =
                    UniswapV3SpotHelperLogic.isCompoundable(id, positionManager);
            } else if (positionManager == address(AlienBaseLogic.POSITION_MANAGER)) {
                (isCompoundable_, accountInfo, compounder) =
                    UniswapV3SpotHelperLogic.isCompoundable(id, positionManager);
            }
        } else {
            if (positionManager == address(SlipstreamLogic.POSITION_MANAGER)) {
                (isCompoundable_, usdValueFees, compounder) = SlipstreamMarginHelperLogic.isCompoundable(id);
            } else if (positionManager == address(UniswapV3Logic.POSITION_MANAGER)) {
                (isCompoundable_, usdValueFees, compounder) =
                    UniswapV3MarginHelperLogic.isCompoundable(id, positionManager);
            } else if (positionManager == address(AlienBaseLogic.POSITION_MANAGER)) {
                (isCompoundable_, usdValueFees, compounder) =
                    UniswapV3MarginHelperLogic.isCompoundable(id, positionManager);
            }
        }
    }
}
