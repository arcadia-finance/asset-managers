/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Base_Test } from "../lib/accounts-v2/test/Base.t.sol";

/// @notice Base test contract with common logic needed by all tests in Asset Managers repo.
abstract contract Base_AssetManagers_Test is Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        Base_Test.setUp();
    }
}
