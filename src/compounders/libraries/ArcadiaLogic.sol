/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { AssetValueAndRiskFactors } from "../../../lib/accounts-v2/src/libraries/AssetValuationLib.sol";
import { IFactory } from "../interfaces/IFactory.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";
import { IRegistry } from "../interfaces/IRegistry.sol";

library ArcadiaLogic {
    // The contract address of the Arcadia Factory.
    IFactory internal constant FACTORY = IFactory(0xDa14Fdd72345c4d2511357214c5B89A919768e59);
    // The contract address of the Arcadia Registry.
    IRegistry internal constant REGISTRY = IRegistry(0xd0690557600eb8Be8391D1d97346e2aab5300d5f);

    /**
     * @notice Returns the trusted USD prices for 1e18 gwei of token0 and token1.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param usdPriceToken0 The USD price of 1e18 gwei of token0, with 18 decimals precision.
     * @param usdPriceToken1 The USD price of 1e18 gwei of token1, with 18 decimals precision.
     */
    function _getValuesInUsd(address token0, address token1)
        internal
        view
        returns (uint256 usdPriceToken0, uint256 usdPriceToken1)
    {
        address[] memory assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
        uint256[] memory assetAmounts = new uint256[](2);
        assetAmounts[0] = 1e18;
        assetAmounts[1] = 1e18;

        AssetValueAndRiskFactors[] memory valuesAndRiskFactors =
            REGISTRY.getValuesInUsd(address(0), assets, new uint256[](2), assetAmounts);

        (usdPriceToken0, usdPriceToken1) = (valuesAndRiskFactors[0].assetValue, valuesAndRiskFactors[1].assetValue);
    }

    /**
     * @notice Encodes the action data for the flash-action used to compound a Uniswap V3 Liquidity Position.
     * @param initiator The address of the initiator.
     * @param nonfungiblePositionManager The contract address of the UniswapV3 NonfungiblePositionManager.
     * @param id The id of the Liquidity Position.
     * @param trustedSqrtPriceX96 The pool sqrtPriceX96 provided at the time of calling compoundFees().
     * @return actionData Bytes string with the encoded actionData.
     */
    function _encodeActionData(
        address initiator,
        address nonfungiblePositionManager,
        uint256 id,
        uint256 trustedSqrtPriceX96
    ) internal pure returns (bytes memory actionData) {
        // Encode Uniswap V3 position that has to be withdrawn from and deposited back into the Account.
        address[] memory assets_ = new address[](1);
        assets_[0] = nonfungiblePositionManager;
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
        bytes memory compoundData = abi.encode(assetData, initiator, trustedSqrtPriceX96);

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, compoundData);
    }
}
