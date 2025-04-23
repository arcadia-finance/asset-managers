/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { FixedPointMathLib } from "../../../../lib/accounts-v2/lib/solmate/src/utils/FixedPointMathLib.sol";
import { stdError } from "../../../../lib/accounts-v2/lib/forge-std/src/StdError.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3Compounder_Fuzz_Test } from "./_UniswapV3Compounder.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "UniswapV3Compounder".
 */
contract Constructor_UniswapV3Compounder_Fuzz_Test is UniswapV3Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_Constructor_UnderflowTolerance(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        UniswapV3Compounder compounder_ = new UniswapV3Compounder(maxTolerance, maxInitiatorShare);

        assertEq(compounder_.MAX_TOLERANCE(), maxTolerance);
        assertEq(compounder_.MAX_INITIATOR_FEE(), maxInitiatorShare);
    }
}
