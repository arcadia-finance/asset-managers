/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Fuzz_Test } from "../Fuzz.t.sol";

import { AutoCompounderExtension } from "../../utils/extensions/AutoCompounderExtension.sol";
import { UniswapV3AMExtension } from "../../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { Utils } from "../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "AutoCompounder" fuzz tests.
 */
abstract contract AutoCompounder_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    AutoCompounderExtension internal autoCompounder;

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAutoCompounder(uint256 compoundThreshold, uint256 initiatorShare, uint256 tolerance) public {
        vm.prank(users.deployer);
        autoCompounder = new AutoCompounderExtension(compoundThreshold, initiatorShare, tolerance);

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(autoCompounder).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in AutoCompounder.
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
        vm.etch(address(autoCompounder), bytecode);
    }
}
