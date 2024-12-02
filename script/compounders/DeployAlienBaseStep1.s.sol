/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.7.6;
pragma abicoder v2;

import { Test } from "../../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { QuoterV2 } from "../../lib/accounts-v2/lib/v3-periphery/contracts/lens/QuoterV2.sol";

contract DeployAlienBaseStep1 is Test {
    constructor() Test() { }

    function run() public {
        uint256 deployer = vm.envUint("PRIVATE_KEY_DEPLOYER_BASE");
        vm.startBroadcast(deployer);
        new QuoterV2(0x3E84D913803b02A4a7f027165E8cA42C14C0FdE7, 0x4200000000000000000000000000000000000006);
        vm.stopBroadcast();
    }
}
