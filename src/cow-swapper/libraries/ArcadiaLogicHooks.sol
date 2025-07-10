/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogicHooks {
    /**
     * @notice Encodes the action data for the withdrawal flash-action.
     * @param token The contract address of the token.
     * @param amount The amount of token to transfer.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeWithdrawal(address token, uint256 amount) internal pure returns (bytes memory actionData) {
        address[] memory assets = new address[](1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory types = new uint256[](1);

        // Encode asset.
        assets[0] = address(token);
        amounts[0] = amount;
        types[0] = 1;

        ActionData memory assetData =
            ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;
        bytes memory emptyBytes;

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, emptyBytes, emptyBytes);
    }

    /**
     * @notice Encodes the action data for the deposit flash-action.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeDeposit(address token, uint256 amount) internal pure returns (bytes memory actionData) {
        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        ActionData memory emptyActionData;
        IPermit2.PermitBatchTransferFrom memory permit;
        bytes memory signature;
        bytes memory actionTargetData = abi.encode(token, amount);

        // Encode the actionData.
        actionData = abi.encode(emptyActionData, emptyActionData, permit, signature, actionTargetData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action is executed.
     * @param token The contract address of the token.
     * @param amount The amount of token to transfer.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDepositData(address token, uint256 amount) internal pure returns (ActionData memory depositData) {
        address[] memory assets = new address[](1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory types = new uint256[](1);

        // Encode asset.
        assets[0] = address(token);
        amounts[0] = amount;
        types[0] = 1;

        depositData = ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });
    }
}
