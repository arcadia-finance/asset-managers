/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";

library ArcadiaLogic {
    /**
     * @notice Encodes the action data for the flash-action used to rebalance a Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @param initiator The address of the initiator.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(address positionManager, uint256 id, address initiator)
        internal
        pure
        returns (bytes memory actionData)
    {
        ActionData memory assetData;
        {
            // Encode position that has to be withdrawn from and deposited back into the Account.
            address[] memory assets_ = new address[](1);
            assets_[0] = positionManager;
            uint256[] memory assetIds_ = new uint256[](1);
            assetIds_[0] = id;
            uint256[] memory assetAmounts_ = new uint256[](1);
            assetAmounts_[0] = 1;
            uint256[] memory assetTypes_ = new uint256[](1);
            assetTypes_[0] = 2;

            assetData = ActionData({
                assets: assets_,
                assetIds: assetIds_,
                assetAmounts: assetAmounts_,
                assetTypes: assetTypes_
            });
        }

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Data required by this contract when Account does the executeAction() callback during the flash-action.
        bytes memory claimData = abi.encode(positionManager, id, initiator);

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, claimData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @param tokens Array with the contract addresses of ERC20 tokens to deposit.
     * @param amounts Array with the amounts of ERC20 tokens to deposit.
     * @param count The number of ERC20 tokens to deposit.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(
        address positionManager,
        uint256 id,
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 count
    ) internal pure returns (ActionData memory depositData) {
        depositData.assets = new address[](count);
        depositData.assetIds = new uint256[](count);
        depositData.assetAmounts = new uint256[](count);
        depositData.assetTypes = new uint256[](count);

        // Add Liquidity Position.
        depositData.assets[0] = positionManager;
        depositData.assetIds[0] = id;
        depositData.assetAmounts[0] = 1;
        depositData.assetTypes[0] = 2;
        if (count == 1) return depositData;

        // Add ERC20 tokens.
        uint256 i = 1;
        for (uint256 j; j < amounts.length; j++) {
            if (amounts[j] > 0) {
                depositData.assets[i] = tokens[j];
                depositData.assetAmounts[i] = amounts[j];
                depositData.assetTypes[i] = 1;
                i++;
            }
        }
    }
}
