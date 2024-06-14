/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { SlipstreamAutoCompounder_Fuzz_Test } from
    "../../auto-compounder/SlipstreamAutoCompounder/_SlipstreamAutoCompounder.fuzz.t.sol";
import { SlipstreamAutoCompoundHelper } from
    "../../../../src/auto-compounder/periphery/SlipstreamAutoCompoundHelper.sol";
import { SlipstreamAutoCompoundHelperExtension } from
    "../../../utils/extensions/SlipstreamAutoCompoundHelperExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "SlipstreamAutoCompoundHelper" fuzz tests.
 */
abstract contract SlipstreamAutoCompoundHelper_Fuzz_Test is SlipstreamAutoCompounder_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SlipstreamAutoCompoundHelperExtension public autoCompoundHelper;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(SlipstreamAutoCompounder_Fuzz_Test) {
        SlipstreamAutoCompounder_Fuzz_Test.setUp();

        deployAutoCompoundHelper();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAutoCompoundHelper() public {
        vm.prank(users.owner);
        autoCompoundHelper = new SlipstreamAutoCompoundHelperExtension(address(autoCompounder));

        // Get the bytecode to overwrite
        bytes memory bytecode = address(autoCompoundHelper).code;

        // Overwrite contract addresses stored as constants in AutoCompounder.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x827922686190790b37229fd06084350E74485b72),
            abi.encodePacked(slipstreamPositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A), abi.encodePacked(cLFactory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0), abi.encodePacked(quoterCL), false
        );
        vm.etch(address(autoCompoundHelper), bytecode);
    }
}
