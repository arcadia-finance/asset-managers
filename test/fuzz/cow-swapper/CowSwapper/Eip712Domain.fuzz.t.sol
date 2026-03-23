/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "eip712Domain" of contract "CowSwapper".
 */
contract Eip712Domain_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_eip712Domain() public view {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            cowSwapper.eip712Domain();

        assertEq(name, "CowSwapper");
        assertEq(version, cowSwapper.VERSION());
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(cowSwapper));
    }
}
