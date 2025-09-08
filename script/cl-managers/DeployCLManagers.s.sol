/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ArcadiaAssetManagers } from "../utils/constants/Shared.sol";
import { Assets, Safes } from "../../lib/accounts-v2/script/utils/constants/Base.sol";
import { Base_AssetManagers_Script } from "../Base.s.sol";
import { CompounderSlipstream } from "../../src/cl-managers/compounders/CompounderSlipstream.sol";
import { CompounderUniswapV3 } from "../../src/cl-managers/compounders/CompounderUniswapV3.sol";
import { CompounderUniswapV4 } from "../../src/cl-managers/compounders/CompounderUniswapV4.sol";
import { Deployers } from "../../lib/accounts-v2/script/utils/constants/Shared.sol";
import { Helpers } from "../utils/constants/Shared.sol";
import { RebalancerSlipstream } from "../../src/cl-managers/rebalancers/RebalancerSlipstream.sol";
import { RebalancerUniswapV3 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV3.sol";
import { RebalancerUniswapV4 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV4.sol";
import { RouterTrampoline } from "../../src/cl-managers/RouterTrampoline.sol";
import { Slipstream, UniswapV3, UniswapV4 } from "../utils/constants/Base.sol";
import { YieldClaimerSlipstream } from "../../src/cl-managers/yield-claimers/YieldClaimerSlipstream.sol";
import { YieldClaimerUniswapV3 } from "../../src/cl-managers/yield-claimers/YieldClaimerUniswapV3.sol";
import { YieldClaimerUniswapV4 } from "../../src/cl-managers/yield-claimers/YieldClaimerUniswapV4.sol";

contract DeployCLManagers is Base_AssetManagers_Script {
    constructor() Base_AssetManagers_Script() { }

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == Deployers.ARCADIA, "Wrong Deployer.");

        vm.startBroadcast(deployer);
        // Deploy Router Trampoline.
        RouterTrampoline routerTrampoline = new RouterTrampoline();

        // Compounders.
        new CompounderSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        new CompounderUniswapV3(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            UniswapV3.POSITION_MANAGER,
            UniswapV3.FACTORY
        );
        new CompounderUniswapV4(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );

        // Rebalancers.
        new RebalancerSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        new RebalancerUniswapV3(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            UniswapV3.POSITION_MANAGER,
            UniswapV3.FACTORY
        );
        new RebalancerUniswapV4(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            address(routerTrampoline),
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );

        // Yield Claimers.
        new YieldClaimerSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        new YieldClaimerUniswapV3(
            Safes.OWNER, ArcadiaAssetManagers.FACTORY, UniswapV3.POSITION_MANAGER, UniswapV3.FACTORY
        );
        new YieldClaimerUniswapV4(
            Safes.OWNER,
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
