/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AccountV1 } from "../../../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { AccountSpot } from "../../../../lib/accounts-v2/src/accounts/AccountSpot.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { StdStorage, stdStorage } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { YieldClaimer } from "../../../../src/yield-routers/YieldClaimer.sol";
import { YieldClaimerExtension } from "../../../../test/utils/extensions/YieldClaimerExtension.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "YieldClaimer" fuzz tests.
 */
abstract contract YieldClaimer_Fuzz_Test is Fuzz_Test {
    using stdStorage for StdStorage;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    // 0,5% to 11% fee on swaps.
    uint256 MIN_INITIATOR_FEE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_FEE = 0.11 * 1e18;
    // 10 % initiator fee
    uint256 INITIATOR_FEE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            STORAGE
    /////////////////////////////////////////////////////////////// */

    address internal initiator;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    YieldClaimerExtension internal yieldClaimer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();

        // Create initiator.
        initiator = createUser("initiator");

        // Deploy Yield Claimer.
        deployYieldClaimer(MAX_INITIATOR_FEE);
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deploySpotAccount() internal {
        vm.prank(users.accountOwner);
        account = AccountV1(address(new AccountSpot(address(factory))));
        stdstore.target(address(factory)).sig(factory.accountIndex.selector).with_key(address(account)).checked_write(2);
        vm.prank(address(factory));
        account.initialize(users.accountOwner, address(registry), address(0));
    }

    function deployYieldClaimer(uint256 maxInitiatorFee) internal {
        deployYieldClaimer(
            address(0), address(0), address(0), address(0), address(0), address(0), address(0), maxInitiatorFee
        );
    }

    function deployYieldClaimer(
        address rewardToken_,
        address slipstreamPositionManager_,
        address stakedSlipstreamAM_,
        address stakedSlipstreamWrapper_,
        address uniswapV3PositionManager_,
        address uniswapV4PositionManager_,
        address weth_,
        uint256 maxInitiatorFee
    ) internal {
        vm.prank(users.owner);
        yieldClaimer = new YieldClaimerExtension(
            rewardToken_,
            slipstreamPositionManager_,
            stakedSlipstreamAM_,
            stakedSlipstreamWrapper_,
            uniswapV3PositionManager_,
            uniswapV4PositionManager_,
            weth_,
            maxInitiatorFee
        );

        bytes memory bytecode = address(yieldClaimer).code;

        // Overwrite contract addresses stored as constants in YieldClaimer.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59),
            abi.encodePacked(address(factory)),
            false
        );
        vm.etch(address(yieldClaimer), bytecode);

        // And : YieldClaimer is allowed as Asset Manager
        vm.prank(users.accountOwner);
        account.setAssetManager(address(yieldClaimer), true);

        // And : Create and set initiator details.
        vm.prank(initiator);
        yieldClaimer.setInitiatorFee(INITIATOR_FEE);
    }
}
