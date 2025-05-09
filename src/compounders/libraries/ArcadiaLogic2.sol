/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { Compounder } from "../Compounder.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action used to compound a Liquidity Position.
     * @param initiator The address of the initiator.
     * @param initiatorParams A struct with the initiator parameters.
     * @return actionData Bytes string with the encoded actionData.
     */
    function _encodeActionData(address initiator, Compounder.InitiatorParams calldata initiatorParams)
        internal
        pure
        returns (bytes memory actionData)
    {
        address[] memory assets = new address[](1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory types = new uint256[](1);

        // Encode liquidity position.
        assets[0] = initiatorParams.positionManager;
        ids[0] = initiatorParams.id;
        amounts[0] = 1;
        types[0] = 2;

        ActionData memory assetData =
            ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Encode the actionData.
        bytes memory compoundData = abi.encode(initiator, initiatorParams);
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, compoundData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action is executed.
     * @param initiatorParams A struct with the initiator parameters.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(Compounder.InitiatorParams memory initiatorParams)
        internal
        pure
        returns (ActionData memory depositData)
    {
        address[] memory assets = new address[](1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory types = new uint256[](1);

        // Encode liquidity position.
        assets[0] = initiatorParams.positionManager;
        ids[0] = initiatorParams.id;
        amounts[0] = 1;
        types[0] = 2;

        depositData = ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });
    }
}
