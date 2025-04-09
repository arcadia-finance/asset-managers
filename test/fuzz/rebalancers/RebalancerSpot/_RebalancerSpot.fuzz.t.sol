/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { RebalancerSpot } from "../../../../src/rebalancers/RebalancerSpot.sol";
import { Rebalancer_Fuzz_Test } from "../Rebalancer/_Rebalancer2.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "RebalancerSpot" fuzz tests.
 */
abstract contract RebalancerSpot_Fuzz_Test is Rebalancer_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    RebalancerSpot internal rebalancerSpot;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Rebalancer_Fuzz_Test) {
        Rebalancer_Fuzz_Test.setUp();

        rebalancerSpot = new RebalancerSpot(MAX_TOLERANCE, MAX_INITIATOR_FEE, MIN_LIQUIDITY_RATIO);

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = address(rebalancerSpot).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite Arcadia contract addresses, stored as constants in Rebalancer.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );

        // Store overwritten bytecode.
        vm.etch(address(rebalancerSpot), bytecode);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/
}
