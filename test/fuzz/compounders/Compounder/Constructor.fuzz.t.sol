/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.26;

import { Compounder_Fuzz_Test } from "./_Compounder.fuzz.t.sol";
import { CompounderExtension } from "../../../utils/extensions/CompounderExtension.sol";

/**
 * @notice Fuzz tests for the function "Constructor" of contract "Compounder".
 */
contract Constructor_Compounder_Fuzz_Test is Compounder_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override { }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_Constructor(
        address arcadiaFactory,
        uint256 maxFee,
        uint256 maxTolerance,
        uint256 maxSlippageRatio
    ) public {
        vm.prank(users.owner);
        CompounderExtension compounder_ =
            new CompounderExtension(arcadiaFactory, maxFee, maxTolerance, maxSlippageRatio);

        assertEq(address(compounder_.ARCADIA_FACTORY()), arcadiaFactory);
        assertEq(compounder_.MAX_TOLERANCE(), maxTolerance);
        assertEq(compounder_.MAX_FEE(), maxFee);
        assertEq(compounder_.MIN_LIQUIDITY_RATIO(), maxSlippageRatio);
    }
}
