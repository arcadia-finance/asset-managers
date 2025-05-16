/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { AlienBaseCompounderSpot } from "../../src/compounders/alien-base/AlienBaseCompounderSpot.sol";
import { CompounderParameters } from "../utils/ConstantsBase.sol";
import { SlipstreamCompounderSpot } from "../../src/compounders/slipstream/SlipstreamCompounderSpot.sol";
import { UniswapV3CompounderSpot } from "../../src/compounders/uniswap-v3/UniswapV3CompounderSpot.sol";

contract DeployCompoundersSpot is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == 0x0f518becFC14125F23b8422849f6393D59627ddB, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        new AlienBaseCompounderSpot(CompounderParameters.INITIATOR_SHARE, CompounderParameters.TOLERANCE);

        new SlipstreamCompounderSpot(CompounderParameters.INITIATOR_SHARE, CompounderParameters.TOLERANCE);

        new UniswapV3CompounderSpot(CompounderParameters.INITIATOR_SHARE, CompounderParameters.TOLERANCE);
        vm.stopBroadcast();
    }
}
