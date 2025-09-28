/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BalancerV2Fixture } from "../../utils/fixtures/balancer-v2/BalancerV2Fixture.f.sol";
import { CowSwapFixture } from "../../utils/fixtures/cow-swap/CowSwapFixture.f.sol";
import { CowSwapperExtension } from "../../utils/extensions/CowSwapperExtension.sol";
import { ERC20Mock } from "../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";
import { WETH9Fixture } from "../../../lib/accounts-v2/test/utils/fixtures/weth9/WETH9Fixture.f.sol";

/**
 * @notice Common logic needed by all "CowSwapper" fuzz tests.
 */
abstract contract CowSwapper_Fuzz_Test is Fuzz_Test, BalancerV2Fixture, CowSwapFixture, WETH9Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint64 internal constant MAX_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CowSwapperExtension internal cowSwapper;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, WETH9Fixture) {
        Fuzz_Test.setUp();

        // Deploy WETH9.
        WETH9Fixture.setUp();

        // Deploy Balancer Vault.
        deployBalancerVault(users.owner, address(weth9));

        // Deploy CowSwap.
        deployCowSwap(users.owner, BALANCER_VAULT);

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts(address(0));

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);

        // Deploy test contract.
        cowSwapper =
            new CowSwapperExtension(users.owner, address(factory), address(flashLoanRouter), address(hooksTrampoline));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function test_dep() public { }
}
