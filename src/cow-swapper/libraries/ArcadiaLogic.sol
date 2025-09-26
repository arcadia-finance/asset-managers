/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action.
     * @param token The contract address of the token.
     * @param amount The amount of token to transfer.
     * @param actionTargetData The data to be passed to the action target.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(address token, uint256 amount, bytes memory actionTargetData)
        internal
        pure
        returns (bytes memory actionData)
    {
        address[] memory assets = new address[](1);
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory types = new uint256[](1);

        // Encode asset.
        assets[0] = address(token);
        amounts[0] = amount;
        types[0] = 1;

        ActionData memory withdrawData =
            ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Encode the actionData.
        actionData = abi.encode(withdrawData, transferFromOwner, permit, signature, actionTargetData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action is executed.
     * @param token The contract address of the token.
     * @param amount The amount of token to transfer.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(address token, uint256 amount) internal pure returns (ActionData memory depositData) {
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
