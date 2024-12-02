/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

import { AlienBaseCompounder } from "../../src/compounders/alien-base/AlienBaseCompounder.sol";
import { AlienBaseCompounderHelper } from "../../src/compounders/alien-base/periphery/AlienBaseCompounderHelper.sol";
import { Parameters } from "../utils/Constants.sol";

contract DeployAlienBaseStep2 is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        alienBaseCompounder =
            new AlienBaseCompounder(Parameters.COMPOUND_THRESHOLD, Parameters.INITIATOR_SHARE, Parameters.TOLERANCE);
        alienBaseCompounderHelper = new AlienBaseCompounderHelper(address(alienBaseCompounder));
        vm.stopBroadcast();
    }
}
