/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ActionData } from "../../../lib/accounts-v2/src/interfaces/IActionBase.sol";
import { AssetValueAndRiskFactors } from "../../../lib/accounts-v2/src/libraries/AssetValuationLib.sol";
import { IFactory } from "../interfaces/IFactory.sol";
import { IPermit2 } from "../../../lib/accounts-v2/src/interfaces/IPermit2.sol";
import { IRegistry } from "../interfaces/IRegistry.sol";
import { RebalancerUniV3Slipstream } from "../RebalancerUniV3Slipstream.sol";
import { StakedSlipstreamLogic } from "./slipstream/StakedSlipstreamLogic.sol";

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
     * @notice Encodes the action data for the flash-action used to rebalance a Liquidity Position.
     * @param asset The contract address of the asset.
     * @param id The id of the Liquidity Position.
     * @param initiator The address of the initiator.
     * @param tickLower The new lower tick to rebalance the position to.
     * @param tickUpper The new upper tick to rebalancer the position to.
     * @param swapData Arbitrary calldata provided by an initiator for a swap.
     * @return actionData Bytes string with the encoded data.
     */
    function _encodeAction(
        address asset,
        uint256 id,
        address initiator,
        int24 tickLower,
        int24 tickUpper,
        bytes calldata swapData
    ) internal pure returns (bytes memory actionData) {
        // Encode Uniswap V3 position that has to be withdrawn from and deposited back into the Account.
        address[] memory assets_ = new address[](1);
        assets_[0] = asset;
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
        bytes memory rebalanceData = abi.encode(assetData, initiator, tickLower, tickUpper, swapData);

        // Encode the actionData.
        actionData = abi.encode(assetData, transferFromOwner, permit, signature, rebalanceData);
    }

    /**
     * @notice Encodes the deposit data after the flash-action used to rebalance the Liquidity Position.
     * @param positionManager The contract address of the Position Manager.
     * @param id The id of the Liquidity Position.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @param count The number of assets to deposit.
     * @param balance0 The amount of token0 to deposit.
     * @param balance1 The amount of token1 to deposit.
     * @param reward The amount of reward token to deposit.
     * @return depositData Bytes string with the encoded data.
     */
    function _encodeDeposit(
        address positionManager,
        uint256 id,
        address token0,
        address token1,
        uint256 count,
        uint256 balance0,
        uint256 balance1,
        uint256 reward
    ) internal pure returns (ActionData memory depositData) {
        depositData.assets = new address[](count);
        depositData.assetIds = new uint256[](count);
        depositData.assetAmounts = new uint256[](count);
        depositData.assetTypes = new uint256[](count);

        // Add newly minted Liquidity Position.
        depositData.assets[0] = positionManager;
        depositData.assetIds[0] = id;
        depositData.assetAmounts[0] = 1;
        depositData.assetTypes[0] = 2;

        // Track the next index for the ERC20 tokens.
        uint256 index = 1;

        if (balance0 > 0) {
            depositData.assets[1] = token0;
            depositData.assetAmounts[1] = balance0;
            depositData.assetTypes[1] = 1;
            index = 2;
        }

        if (balance1 > 0) {
            depositData.assets[index] = token1;
            depositData.assetAmounts[index] = balance1;
            depositData.assetTypes[index] = 1;
            ++index;
        }

        if (reward > 0) {
            depositData.assets[index] = StakedSlipstreamLogic.REWARD_TOKEN;
            depositData.assetAmounts[index] = reward;
            depositData.assetTypes[index] = 1;
        }
    }
}
