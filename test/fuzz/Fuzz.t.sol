/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import {
    ArcadiaAccountsFixture
} from "../../lib/accounts-v2/test/utils/fixtures/arcadia-accounts/ArcadiaAccountsFixture.f.sol";
import { Base_AssetManagers_Test } from "../Base.t.sol";
import { Base_Test } from "../../lib/accounts-v2/test/Base.t.sol";
import { TickMath } from "../../lib/accounts-v2/src/asset-modules/UniswapV3/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all fuzz tests.
 */
abstract contract Fuzz_Test is Base_AssetManagers_Test, ArcadiaAccountsFixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint160 internal constant BOUND_SQRT_PRICE_UPPER = type(uint120).max;
    // forge-lint: disable-start(mixed-case-variable)
    int24 internal BOUND_TICK_UPPER = TickMath.getTickAtSqrtRatio(BOUND_SQRT_PRICE_UPPER);
    int24 internal BOUND_TICK_LOWER = -BOUND_TICK_UPPER;
    uint160 internal BOUND_SQRT_PRICE_LOWER = TickMath.getSqrtRatioAtTick(BOUND_TICK_LOWER);
    // forge-lint: disable-end(mixed-case-variable)

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override(Base_AssetManagers_Test, Base_Test) {
        Base_AssetManagers_Test.setUp();
    }
}
