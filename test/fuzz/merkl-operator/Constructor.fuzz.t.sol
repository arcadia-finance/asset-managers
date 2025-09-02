/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { MerklOperator_Fuzz_Test } from "./_MerklOperator.fuzz.t.sol";
import { MerklOperatorExtension } from "../../utils/extensions/MerklOperatorExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "MerklOperator".
 */
contract Constructor_MerklOperator_Fuzz_Test is MerklOperator_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address distributor_) public {
        MerklOperatorExtension merklOperator_ = new MerklOperatorExtension(owner_, arcadiaFactory, distributor_);

        assertEq(merklOperator_.owner(), owner_);
        assertEq(address(merklOperator_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(merklOperator_.MERKL_DISTRIBUTOR()), distributor_);
    }
}
