/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action used to compound a Uniswap V3 Liquidity Position.
     * @param initiator The address of the initiator.
     * @param positionManager The address of the contract that holds the position.
     * @param id The id of the Liquidity Position.
     * @return actionData Bytes string with the encoded actionData.
     */
    function _encodeActionData(address initiator, address positionManager, uint256 id)
        internal
        pure
        returns (bytes memory actionData)
    {
        // Encode the asset that has to be withdrawn from and deposited back into the Account.
        address[] memory assets_ = new address[](1);
        assets_[0] = positionManager;
        uint256[] memory assetIds_ = new uint256[](1);
        assetIds_[0] = id;
        uint256[] memory assetAmounts_ = new uint256[](1);
        assetAmounts_[0] = 1;
        uint256[] memory assetTypes_ = new uint256[](1);
        assetTypes_[0] = 2;

        ActionData memory assetData =
            ActionData({ assets: assets_, assetIds: assetIds_, assetAmounts: assetAmounts_, assetTypes: assetTypes_ });

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Data required by this contract when Account does the executeAction() callback during the flash-action.
        bytes memory claimData = abi.encode(assetData, initiator);

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, claimData);
    }
}
