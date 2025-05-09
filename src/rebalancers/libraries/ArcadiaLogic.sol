/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";
import { Rebalancer } from "../Rebalancer.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action used to rebalance a Liquidity Position.
     * @param initiator The address of the initiator.
     * @param initiatorParams A struct with the initiator parameters.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(
        address initiator,
        Rebalancer.InitiatorParams calldata initiatorParams,
        address token0,
        address token1
    ) internal pure returns (bytes memory actionData) {
        // Calculate the number of assets to encode.
        uint256 count = 1;
        if (initiatorParams.amount0 > 0) count++;
        if (initiatorParams.amount1 > 0) count++;

        address[] memory assets = new address[](count);
        uint256[] memory ids = new uint256[](count);
        uint256[] memory amounts = new uint256[](count);
        uint256[] memory types = new uint256[](count);

        // Encode liquidity position.
        assets[0] = initiatorParams.positionManager;
        ids[0] = initiatorParams.oldId;
        amounts[0] = 1;
        types[0] = 2;

        // Encode underlying assets of the liquidity position.
        uint256 index = 1;
        if (initiatorParams.amount0 > 0) {
            assets[1] = token0;
            amounts[1] = initiatorParams.amount0;
            types[1] = 1;
            index = 2;
        }
        if (initiatorParams.amount1 > 0) {
            assets[index] = token1;
            amounts[index] = initiatorParams.amount1;
            types[index] = 1;
        }

        ActionData memory assetData =
            ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Encode the actionData.
        bytes memory actionTargetData = abi.encode(initiator, initiatorParams);
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, actionTargetData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action is executed.
     * @param positionManager The address of the position manager.
     * @param id The id of the Liquidity Position.
     * @param count The number of tokens to deposit.
     * @param tokens The contract addresses of the tokens to deposit.
     * @param balances The balances of the tokens to deposit.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(
        address positionManager,
        uint256 id,
        uint256 count,
        address[] memory tokens,
        uint256[] memory balances
    ) internal pure returns (ActionData memory depositData) {
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
        if (count > 1) {
            uint256 i = 1;
            for (uint256 j; j < balances.length; j++) {
                if (balances[j] > 0) {
                    assets[i] = tokens[j];
                    amounts[i] = balances[j];
                    types[i] = 1;
                    i++;
                }
            }
        }

        depositData = ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });
    }
}
