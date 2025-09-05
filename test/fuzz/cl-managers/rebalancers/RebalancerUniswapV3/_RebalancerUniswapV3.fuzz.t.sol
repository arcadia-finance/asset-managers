/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { RebalancerUniswapV3Extension } from "../../../../utils/extensions/RebalancerUniswapV3Extension.sol";
import { RouterTrampoline } from "../../../../../src/cl-managers/RouterTrampoline.sol";
import { UniswapV3_Fuzz_Test } from "../../base/UniswapV3/_UniswapV3.fuzz.t.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerUniswapV3" fuzz tests.
 */
abstract contract RebalancerUniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterTrampoline internal routerTrampoline;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerUniswapV3Extension internal rebalancer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV3_Fuzz_Test) {
        UniswapV3_Fuzz_Test.setUp();

        // Deploy Router Trampoline.
        routerTrampoline = new RouterTrampoline();

        // Deploy test contract.
        rebalancer = new RebalancerUniswapV3Extension(
            users.owner,
            address(factory),
            address(routerTrampoline),
            address(nonfungiblePositionManager),
            address(uniswapV3Factory)
        );

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = address(rebalancer).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Store overwritten bytecode.
        vm.etch(address(rebalancer), bytecode);
    }
}
