/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { ArcadiaAssetManagers } from "../utils/constants/Shared.sol";
import { Assets } from "../../lib/accounts-v2/script/utils/constants/Base.sol";
import { Base_AssetManagers_Script } from "../Base.s.sol";
import { Deployers } from "../../lib/accounts-v2/script/utils/constants/Shared.sol";
import { RebalancerSlipstream } from "../../src/cl-managers/rebalancers/RebalancerSlipstream.sol";
import { RebalancerUniswapV3 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV3.sol";
import { RebalancerUniswapV4 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV4.sol";
import { Slipstream, UniswapV3, UniswapV4 } from "../utils/constants/Base.sol";

contract DeployRebalancers is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == Deployers.ARCADIA, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        new RebalancerSlipstream(
            ArcadiaAssetManagers.FACTORY,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        new RebalancerUniswapV3(ArcadiaAssetManagers.FACTORY, UniswapV3.POSITION_MANAGER, UniswapV3.FACTORY);
        new RebalancerUniswapV4(
            ArcadiaAssetManagers.FACTORY,
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );
        vm.stopBroadcast();
    }

    function test_deploy() public {
        vm.skip(true);
    }
}
