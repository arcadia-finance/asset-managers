/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ArcadiaAssetManagers, Helpers } from "../utils/constants/Shared.sol";
import { Assets, Merkl } from "../../lib/accounts-v2/script/utils/constants/Base.sol";
import { Base_AssetManagers_Script } from "../Base.s.sol";
import { CompounderSlipstream } from "../../src/cl-managers/compounders/CompounderSlipstream.sol";
import { CompounderUniswapV3 } from "../../src/cl-managers/compounders/CompounderUniswapV3.sol";
import { CompounderUniswapV4 } from "../../src/cl-managers/compounders/CompounderUniswapV4.sol";
import { Deployers, Safes } from "../../lib/accounts-v2/script/utils/constants/Shared.sol";
import { MerklOperator } from "../../src/merkl-operator/MerklOperator.sol";
import { RebalancerSlipstream } from "../../src/cl-managers/rebalancers/RebalancerSlipstream.sol";
import { RebalancerUniswapV3 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV3.sol";
import { RebalancerUniswapV4 } from "../../src/cl-managers/rebalancers/RebalancerUniswapV4.sol";
import { Slipstream, UniswapV3, UniswapV4 } from "../utils/constants/Base.sol";
import { YieldClaimerSlipstream } from "../../src/cl-managers/yield-claimers/YieldClaimerSlipstream.sol";
import { YieldClaimerUniswapV3 } from "../../src/cl-managers/yield-claimers/YieldClaimerUniswapV3.sol";
import { YieldClaimerUniswapV4 } from "../../src/cl-managers/yield-claimers/YieldClaimerUniswapV4.sol";

contract DeployCLManagers is Base_AssetManagers_Script {
    CompounderSlipstream internal compounderSlipstream;
    CompounderUniswapV3 internal compounderUniswapV3;
    CompounderUniswapV4 internal compounderUniswapV4;
    RebalancerSlipstream internal rebalancerSlipstream;
    RebalancerUniswapV3 internal rebalancerUniswapV3;
    RebalancerUniswapV4 internal rebalancerUniswapV4;
    YieldClaimerSlipstream internal yieldClaimerSlipstream;
    YieldClaimerUniswapV3 internal yieldClaimerUniswapV3;
    YieldClaimerUniswapV4 internal yieldClaimerUniswapV4;
    MerklOperator internal merklOperator;

    function run() public {
        // Sanity check that we use the correct priv key.
        require(vm.addr(deployer) == Deployers.ARCADIA, "Wrong Deployer.");

        vm.createSelectFork(vm.envString("RPC_URL_BASE"));
        assertEq(8453, block.chainid);

        vm.startBroadcast(deployer);
        // Compounders.
        compounderSlipstream = new CompounderSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        compounderUniswapV3 = new CompounderUniswapV3(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            UniswapV3.POSITION_MANAGER,
            UniswapV3.FACTORY
        );
        compounderUniswapV4 = new CompounderUniswapV4(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );

        // Rebalancers.
        rebalancerSlipstream = new RebalancerSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        rebalancerUniswapV3 = new RebalancerUniswapV3(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            UniswapV3.POSITION_MANAGER,
            UniswapV3.FACTORY
        );
        rebalancerUniswapV4 = new RebalancerUniswapV4(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Helpers.ROUTER_TRAMPOLINE,
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );

        // Yield Claimers.
        yieldClaimerSlipstream = new YieldClaimerSlipstream(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            Slipstream.POSITION_MANAGER,
            Slipstream.FACTORY,
            Slipstream.POOL_IMPLEMENTATION,
            Assets.AERO().asset,
            ArcadiaAssetManagers.STAKED_SLIPSTREAM_AM,
            ArcadiaAssetManagers.WRAPPED_STAKED_SLIPSTREAM
        );
        yieldClaimerUniswapV3 = new YieldClaimerUniswapV3(
            Safes.OWNER, ArcadiaAssetManagers.FACTORY, UniswapV3.POSITION_MANAGER, UniswapV3.FACTORY
        );
        yieldClaimerUniswapV4 = new YieldClaimerUniswapV4(
            Safes.OWNER,
            ArcadiaAssetManagers.FACTORY,
            UniswapV4.POSITION_MANAGER,
            UniswapV4.PERMIT_2,
            UniswapV4.POOL_MANAGER,
            Assets.WETH().asset
        );

        // Merkl Operator.
        merklOperator = new MerklOperator(Safes.OWNER, ArcadiaAssetManagers.FACTORY, Merkl.DISTRIBUTOR);
        vm.stopBroadcast();

        test_deploy();
    }

    function test_deploy() internal {
        vm.skip(false);

        emit log_named_address("CompounderSlipstream", address(compounderSlipstream));
        emit log_named_address("CompounderUniswapV3", address(compounderUniswapV3));
        emit log_named_address("CompounderUniswapV4", address(compounderUniswapV4));
        emit log_named_address("RebalancerSlipstream", address(rebalancerSlipstream));
        emit log_named_address("RebalancerUniswapV3", address(rebalancerUniswapV3));
        emit log_named_address("RebalancerUniswapV4", address(rebalancerUniswapV4));
        emit log_named_address("YieldClaimerSlipstream", address(yieldClaimerSlipstream));
        emit log_named_address("YieldClaimerUniswapV3", address(yieldClaimerUniswapV3));
        emit log_named_address("YieldClaimerUniswapV4", address(yieldClaimerUniswapV4));
        emit log_named_address("MerklOperator", address(merklOperator));
    }
}
