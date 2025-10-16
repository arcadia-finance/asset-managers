/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BalancerV2Fixture } from "../../../utils/fixtures/balancer-v2/BalancerV2Fixture.f.sol";
import { CowSwapFixture } from "../../../utils/fixtures/cow-swap/CowSwapFixture.f.sol";
import { CowSwapperExtension } from "../../../utils/extensions/CowSwapperExtension.sol";
import { DefaultOrderHookExtension } from "../../../utils/extensions/DefaultOrderHookExtension.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { WETH9Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/weth9/WETH9Fixture.f.sol";

/**
 * @notice Common logic needed by all "DefaultOrderHook" fuzz tests.
 */
abstract contract DefaultOrderHook_Fuzz_Test is Fuzz_Test, BalancerV2Fixture, CowSwapFixture, WETH9Fixture {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CowSwapperExtension internal cowSwapper;
    DefaultOrderHookExtension internal orderHook;

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

        // Deploy CoW Swapper
        cowSwapper =
            new CowSwapperExtension(users.owner, address(factory), address(flashLoanRouter), address(hooksTrampoline));

        // Deploy mocked order hook.
        orderHook = new DefaultOrderHookExtension(address(cowSwapper));
    }
}
