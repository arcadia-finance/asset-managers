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
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(
        address initiator,
        Rebalancer.InitiatorParams calldata params,
        address token0,
        address token1
    ) internal pure returns (bytes memory actionData) {
        uint256 count = 1;
        if (params.amount0 > 0) count++;
        if (params.amount1 > 0) count++;

        ActionData memory assetData;
        {
            address[] memory assets = new address[](count);
            uint256[] memory ids = new uint256[](count);
            uint256[] memory amounts = new uint256[](count);
            uint256[] memory types = new uint256[](count);

            // Encode Uniswap V3 position.
            assets[0] = params.positionManager;
            ids[0] = params.oldId;
            amounts[0] = 1;
            types[0] = 2;

            // Encode underlying assets of the Uniswap V3 position.
            uint256 index = 1;
            if (params.amount0 > 0) {
                assets[1] = token0;
                amounts[1] = params.amount0;
                types[1] = 1;
                index = 2;
            }
            if (params.amount1 > 0) {
                assets[index] = token1;
                amounts[index] = params.amount1;
                types[index] = 1;
            }

            assetData = ActionData({ assets: assets, assetIds: ids, assetAmounts: amounts, assetTypes: types });
        }

        // Empty data objects that have to be encoded when calling flashAction(), but that are not used for this specific flash-action.
        bytes memory signature;
        ActionData memory transferFromOwner;
        IPermit2.PermitBatchTransferFrom memory permit;

        // Encode the actionData.
        bytes memory actionTargetData = abi.encode(initiator, params);
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, actionTargetData);
    }

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

        assets = new address[](count);
        ids = new uint256[](count);
        amounts = new uint256[](count);
        types = new uint256[](count);

        // Add Liquidity Position.
        assets[0] = positionManager;
        ids[0] = id;
        amounts[0] = 1;
        types[0] = 2;

        // Add ERC20 tokens.
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
