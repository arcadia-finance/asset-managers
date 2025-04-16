/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AeroClaimer } from "../../../../src/token-claimers/AeroClaimer.sol";
import { StakedSlipstreamAM_Fuzz_Test } from
    "../../../../lib/accounts-v2/test/fuzz/asset-modules/StakedSlipstreamAM/_StakedSlipstreamAM.fuzz.t.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "AeroClaimer" fuzz tests.
 */
abstract contract AeroClaimer_Fuzz_Test is StakedSlipstreamAM_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    // 0,5% to 11% fee on swaps.
    uint256 MIN_INITIATOR_SHARE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_SHARE = 0.11 * 1e18;
    // 10 % initiator fee
    uint256 INITIATOR_SHARE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            STORAGE
    /////////////////////////////////////////////////////////////// */

    address internal initiator;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    AeroClaimer internal aeroClaimer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(StakedSlipstreamAM_Fuzz_Test) {
        StakedSlipstreamAM_Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        // Deploy Aero Claimer.
        deployAeroClaimer(MAX_INITIATOR_SHARE);

        // And : AeroClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(aeroClaimer), true);

        // And : Create and set initiator details.
        initiator = createUser("initiator");
        vm.prank(initiator);
        aeroClaimer.setInitiatorFee(INITIATOR_SHARE);

        // And : Set the initiator for the account.
        vm.prank(users.accountOwner);
        aeroClaimer.setInitiator(address(account), initiator);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployAeroClaimer(uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        aeroClaimer = new AeroClaimer(maxInitiatorShare);

        bytes memory bytecode = address(aeroClaimer).code;

        // Overwrite contract addresses stored as constants in AeroClaimer.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1),
            abi.encodePacked(stakedSlipstreamAM),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x940181a94A35A4569E4529A3CDfB74e38FD98631), abi.encodePacked(AERO), false
        );

        vm.etch(address(aeroClaimer), bytecode);
    }
}
