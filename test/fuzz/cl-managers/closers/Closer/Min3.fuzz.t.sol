/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_min3" of contract "Closer".
 */
contract Min3_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_min3_FirstSmallest(uint256 a, uint256 b, uint256 c) public view {
        // Given: a is smallest.
        a = bound(a, 0, type(uint64).max - 1);
        b = bound(b, a + 1, type(uint64).max);
        c = bound(c, a + 1, type(uint64).max);

        // When: Calling min3.
        uint256 result = closer.min3(a, b, c);

        // Then: Should return a.
        assertEq(result, a);
    }

    function testFuzz_Success_min3_SecondSmallest(uint256 a, uint256 b, uint256 c) public view {
        // Given: b is smallest.
        b = bound(b, 0, type(uint64).max - 1);
        a = bound(a, b + 1, type(uint64).max);
        c = bound(c, b + 1, type(uint64).max);

        // When: Calling min3.
        uint256 result = closer.min3(a, b, c);

        // Then: Should return b.
        assertEq(result, b);
    }

    function testFuzz_Success_min3_ThirdSmallest(uint256 a, uint256 b, uint256 c) public view {
        // Given: c is smallest.
        c = bound(c, 0, type(uint64).max - 1);
        a = bound(a, c + 1, type(uint64).max);
        b = bound(b, c + 1, type(uint64).max);

        // When: Calling min3.
        uint256 result = closer.min3(a, b, c);

        // Then: Should return c.
        assertEq(result, c);
    }

    function testFuzz_Success_min3_AllEqual(uint256 value) public view {
        // Given: All values equal.
        value = bound(value, 0, type(uint256).max);

        // When: Calling min3.
        uint256 result = closer.min3(value, value, value);

        // Then: Should return the value.
        assertEq(result, value);
    }

    function testFuzz_Success_min3_TwoEqual(uint256 min, uint256 max) public view {
        // Given: Two values equal and smallest.
        min = bound(min, 0, type(uint128).max);
        max = bound(max, min + 1, type(uint256).max);

        // When: Calling min3 with two equal smallest values.
        uint256 result1 = closer.min3(min, min, max);
        uint256 result2 = closer.min3(min, max, min);
        uint256 result3 = closer.min3(max, min, min);

        // Then: Should always return min.
        assertEq(result1, min);
        assertEq(result2, min);
        assertEq(result3, min);
    }
}
