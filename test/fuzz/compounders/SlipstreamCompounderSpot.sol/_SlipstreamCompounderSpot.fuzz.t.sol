/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { SlipstreamCompounderSpot } from "../../../../src/compounders/slipstream/SlipstreamCompounderSpot.sol";
import { SlipstreamCompounder_Fuzz_Test } from "../SlipstreamCompounder/_SlipstreamCompounder.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "SlipstreamCompounderSpot" fuzz tests.
 */
abstract contract SlipstreamCompounderSpot_Fuzz_Test is SlipstreamCompounder_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    SlipstreamCompounderSpot internal compounderSpot;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(SlipstreamCompounder_Fuzz_Test) {
        SlipstreamCompounder_Fuzz_Test.setUp();

        deployCompounderSpot(INITIATOR_SHARE, TOLERANCE);

        vm.prank(users.accountOwner);
        account.setAssetManager(address(compounderSpot), true);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployCompounderSpot(uint256 initiatorShare, uint256 tolerance) public {
        vm.prank(users.owner);
        compounderSpot = new SlipstreamCompounderSpot(initiatorShare, tolerance);

        // Overwrite code hash of the CLPool.
        bytes memory bytecode = address(compounderSpot).code;

        // Overwrite contract addresses stored as constants in Compounder.
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
        vm.etch(address(compounderSpot), bytecode);
    }
}
