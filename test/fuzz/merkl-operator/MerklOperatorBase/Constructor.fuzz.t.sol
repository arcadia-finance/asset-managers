/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MerklOperatorBase_Fuzz_Test } from "./_MerklOperatorBase.fuzz.t.sol";
import { MerklOperatorBaseExtension } from "../../../utils/extensions/MerklOperatorBaseExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "MerklOperatorBase".
 */
contract Constructor_MerklOperatorBase_Fuzz_Test is MerklOperatorBase_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(address owner_, address arcadiaFactory, address distributor_) public {
        MerklOperatorBaseExtension merklOperator_ = new MerklOperatorBaseExtension(owner_, arcadiaFactory, distributor_);

        assertEq(merklOperator_.owner(), owner_);
        assertEq(address(merklOperator_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(address(merklOperator_.MERKL_DISTRIBUTOR()), distributor_);
    }
}
