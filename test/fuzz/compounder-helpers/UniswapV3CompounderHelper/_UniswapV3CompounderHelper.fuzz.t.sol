/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3Compounder_Fuzz_Test } from "../../compounders/UniswapV3Compounder/_UniswapV3Compounder.fuzz.t.sol";
import { UniswapV3CompounderHelper } from
    "../../../../src/compounders/periphery/libraries/margin-accounts/uniswap-v3/UniswapV3CompounderHelper.sol";
import { UniswapV3CompounderHelperExtension } from "../../../utils/extensions/UniswapV3CompounderHelperExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "UniswapV3CompounderHelper" fuzz tests.
 */
abstract contract UniswapV3CompounderHelper_Fuzz_Test is UniswapV3Compounder_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    UniswapV3CompounderHelperExtension public compounderHelper;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV3Compounder_Fuzz_Test) {
        UniswapV3Compounder_Fuzz_Test.setUp();

        deployCompounderHelper();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployCompounderHelper() public {
        vm.prank(users.owner);
        compounderHelper = new UniswapV3CompounderHelperExtension(address(compounder));

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(compounderHelper).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in CompounderViews.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1),
            abi.encodePacked(nonfungiblePositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x33128a8fC17869897dcE68Ed026d694621f6FDfD),
            abi.encodePacked(uniswapV3Factory),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a), abi.encodePacked(quoter), false
        );
        vm.etch(address(compounderHelper), bytecode);
    }
}
