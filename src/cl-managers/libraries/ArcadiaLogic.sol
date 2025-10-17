/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action used to manage a Liquidity Position.
     * @param positionManager The address of the position manager.
     * @param id The id of the Liquidity Position.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param amount0 The amount of token0 to transfer.
     * @param amount1 The amount of token1 to transfer.
     * @param actionTargetData The data to be passed to the action target.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(
        address positionManager,
        uint256 id,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bytes memory actionTargetData
    ) internal pure returns (bytes memory actionData) {
        // Calculate the number of assets to encode.
        uint256 count = 1;
        if (amount0 > 0) count++;
        if (amount1 > 0) count++;

        address[] memory assets = new address[](count);
        uint256[] memory ids = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        uint256[] memory types = new uint256[](count);

        // Encode liquidity position.
        assets[0] = positionManager;
        ids[0] = id;
        amounts[0] = 1;
        types[0] = 2;

        // Encode underlying assets of the liquidity position.
        uint256 index = 1;
        if (amount0 > 0) {
            assets[1] = token0;
            amounts[1] = amount0;
            types[1] = 1;
            index = 2;
        }
        if (amount1 > 0) {
            assets[index] = token1;
            amounts[index] = amount1;
            types[index] = 1;
        }

        ActionData memory assetData =
            ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, actionTargetData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action is executed.
     * @param positionManager The address of the position manager.
     * @param id The id of the Liquidity Position.
     * @param tokens The contract addresses of the tokens to deposit.
     * @param balances The balances of the tokens to deposit.
     * @param count The number of tokens to deposit.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(
        address positionManager,
        uint256 id,
        address[] memory tokens,
        uint256[] memory balances,
        uint256 count
    ) internal pure returns (ActionData memory depositData) {
        address[] memory assets = new address[](count);
        uint256[] memory ids = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        uint256[] memory types = new uint256[](count);

        // Encode liquidity position.
        uint256 i;
        if (id > 0) {
            assets[0] = positionManager;
            ids[0] = id;
            amounts[0] = 1;
            types[0] = 2;
            i = 1;
        }

        // Encode underlying assets of the liquidity position.
        for (uint256 j; j < balances.length; j++) {
            if (balances[j] > 0) {
                assets[i] = tokens[j];
                amounts[i] = balances[j];
                types[i] = 1;
                i++;
            }
        }

        depositData = ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });
    }
}
