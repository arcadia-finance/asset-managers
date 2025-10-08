/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Base_AssetManagers_Script } from "../Base.s.sol";
import { Compounders, Rebalancers, YieldClaimers } from "../utils/constants/Shared.sol";
import { Guardian } from "../../src/guardian/Guardian.sol";
import { Safes } from "../../lib/accounts-v2/script/utils/constants/Shared.sol";
import { SafesAssetManagers } from "../utils/constants/Shared.sol";

contract SetGuardians is Base_AssetManagers_Script {
    function run() public {
        // Set Guardian for Asset Managers.
        setGuardian(Compounders.SLIPSTREAM);
        setGuardian(Compounders.UNISWAP_V3);
        setGuardian(Compounders.UNISWAP_V4);
        setGuardian(Rebalancers.SLIPSTREAM);
        setGuardian(Rebalancers.UNISWAP_V3);
        setGuardian(Rebalancers.UNISWAP_V4);
        setGuardian(YieldClaimers.SLIPSTREAM);
        setGuardian(YieldClaimers.UNISWAP_V3);
        setGuardian(YieldClaimers.UNISWAP_V4);

        // Create and write away batched transaction data to be signed with Safe.
        bytes memory data = createBatchedData(Safes.OWNER);
        vm.writeLine(PATH, vm.toString(data));
    }

    function setGuardian(address assetManager) internal {
        addToBatch(Safes.OWNER, assetManager, abi.encodeCall(Guardian.changeGuardian, (SafesAssetManagers.GUARDIAN)));
    }
}
