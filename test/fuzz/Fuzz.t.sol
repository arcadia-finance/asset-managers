/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { ArcadiaAccountsFixture } from
    "../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/ArcadiaAccountsFixture.f.sol";
import { Base_AssetManagers_Test } from "../Base.t.sol";
import { Base_Test } from "../../lib/accounts-v2/test/Base.t.sol";

/**
 * @notice Common logic needed by all fuzz tests.
 */
abstract contract Fuzz_Test is Base_AssetManagers_Test, ArcadiaAccountsFixture {
    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override(Base_AssetManagers_Test, Base_Test) {
        Base_AssetManagers_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia  Accounts Contracts.
        deployArcadiaAccounts();
    }
}
