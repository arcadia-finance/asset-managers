/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { Base_AssetManagers_Script } from "../Base.s.sol";
import { Compounders, Rebalancers, YieldClaimers } from "../utils/constants/Shared.sol";
import { Guardian } from "../../src/guardian/Guardian.sol";
import { SafesAssetManagers } from "../utils/constants/Base.sol";

contract CircuitBreaker is Base_AssetManagers_Script {
    address internal SAFE = SafesAssetManagers.GUARDIAN;

    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Pause Asset Managers.
        pause(Compounders.SLIPSTREAM);
        pause(Compounders.UNISWAP_V3);
        pause(Compounders.UNISWAP_V4);
        pause(Rebalancers.SLIPSTREAM);
        pause(Rebalancers.UNISWAP_V3);
        pause(Rebalancers.UNISWAP_V4);
        pause(YieldClaimers.SLIPSTREAM);
        pause(YieldClaimers.UNISWAP_V3);
        pause(YieldClaimers.UNISWAP_V4);

        // Create and write away batched transaction data to be signed with Safe.
        bytes memory data = createBatchedData(SAFE);
        vm.writeLine(PATH, vm.toString(data));
    }

    function pause(address target) internal {
        addToBatch(SAFE, target, abi.encodeCall(Guardian.pause, ()));
    }
}
