/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";

contract DeployRebalancers is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        vm.startBroadcast(deployer);
        vm.stopBroadcast();
    }
}
