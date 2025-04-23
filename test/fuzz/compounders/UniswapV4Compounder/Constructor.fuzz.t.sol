/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4Compounder_Fuzz_Test } from "./_UniswapV4Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "UniswapV4Compounder".
 */
contract Constructor_UniswapV4Compounder_Fuzz_Test is UniswapV4Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        UniswapV4Compounder compounder_ = new UniswapV4Compounder(maxTolerance, maxInitiatorShare);

        assertEq(compounder_.MAX_TOLERANCE(), maxTolerance);
        assertEq(compounder_.MAX_INITIATOR_FEE(), maxInitiatorShare);
    }
}
