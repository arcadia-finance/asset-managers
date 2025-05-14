/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { CompounderUniswapV3Extension } from "../../../utils/extensions/CompounderUniswapV3Extension.sol";
import { UniswapV3_Fuzz_Test } from "../../base/UniswapV3/_UniswapV3.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "CompounderUniswapV3" fuzz tests.
 */
abstract contract CompounderUniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CompounderUniswapV3Extension internal compounder;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV3_Fuzz_Test) {
        UniswapV3_Fuzz_Test.setUp();

        // Deploy test contract.
        compounder = new CompounderUniswapV3Extension(
            address(factory), address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = address(compounder).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Store overwritten bytecode.
        vm.etch(address(compounder), bytecode);
    }
}
