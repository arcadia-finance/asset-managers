/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { Closer_Fuzz_Test } from "./_Closer.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "_getIndex" of contract "Closer".
 */
contract GetIndex_Closer_Fuzz_Test is Closer_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Closer_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_getIndex_TokenInArray(address token, uint8 arrayLength, uint8 tokenIndex) public view {
        // Given: Token exists in array.
        arrayLength = uint8(bound(arrayLength, 1, 10));
        tokenIndex = uint8(bound(tokenIndex, 0, arrayLength - 1));
        address[] memory tokens = new address[](arrayLength);
        for (uint256 i; i < arrayLength; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tokens[i] = address(uint160(i + 1));
        }
        tokens[tokenIndex] = token;

        // When: Calling getIndex.
        (address[] memory updatedTokens, uint256 index) = closer.getIndex(tokens, token);

        // Then: Should return correct index and unchanged array.
        assertEq(index, tokenIndex);
        assertEq(updatedTokens.length, arrayLength);
        assertEq(updatedTokens[tokenIndex], token);
    }

    function testFuzz_Success_getIndex_TokenNotInArray(address token, uint8 arrayLength) public view {
        // Given: Token does not exist in array.
        arrayLength = uint8(bound(arrayLength, 0, 10));

        address[] memory tokens = new address[](arrayLength);
        for (uint256 i; i < arrayLength; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            tokens[i] = address(uint160(i + 1));
            vm.assume(token != tokens[i]);
        }

        // When: Calling getIndex.
        (address[] memory updatedTokens, uint256 index) = closer.getIndex(tokens, token);

        // Then: Should return new index and expanded array.
        assertEq(index, arrayLength);
        assertEq(updatedTokens.length, arrayLength + 1);
        assertEq(updatedTokens[index], token);

        // And: Original tokens are preserved.
        for (uint256 i; i < arrayLength; i++) {
            assertEq(updatedTokens[i], tokens[i]);
        }
    }
}
