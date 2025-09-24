/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Base_Script } from "../lib/accounts-v2/script/Base.s.sol";

abstract contract Base_AssetManagers_Script is Base_Script {
    constructor() {
        deployer = vm.envUint("PRIVATE_KEY_DEPLOYER");
    }
}
