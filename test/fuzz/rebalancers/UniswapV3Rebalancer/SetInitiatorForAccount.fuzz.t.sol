/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { UniswapV3Rebalancer } from "../../../../src/rebalancers/uniswap-v3/UniswapV3Rebalancer.sol";
import { UniswapV3Rebalancer_Fuzz_Test } from "./_UniswapV3Rebalancer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "setInitiatorForAccount" of contract "UniswapV3Rebalancer".
 */
contract SetInitiatorForAccount_UniswapV3Rebalancer_Fuzz_Test is UniswapV3Rebalancer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        UniswapV3Rebalancer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_setInitiatorForAccount(address owner, address initiator, address account_) public {
        // When : A randon address calls setInitiator on the rebalancer
        vm.prank(owner);
        rebalancer.setInitiatorForAccount(initiator, account_);

        // Then : Initiator should be set for that address
        assertEq(rebalancer.ownerToAccountToInitiator(owner), initiator);
    }
}
