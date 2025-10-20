/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

/**
 * @notice Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 * @dev based on EIP-1271 reference implementation: https://eips.ethereum.org/EIPS/eip-1271.
 */
library ECDSA {
    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidLength();
    error InvalidSignature();
    error InvalidSigner();

    /* ///////////////////////////////////////////////////////////////
                            LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the address that signed a hashed message.
     * @param hash_ Hash of message that was signed.
     * @param signature  Signature encoded as (bytes32 r, bytes32 s, uint8 v).
     */
    function recoverSigner(bytes32 hash_, bytes memory signature) internal pure returns (address signer) {
        if (signature.length != 65) revert InvalidLength();

        bytes32 r;
        bytes32 s;
        uint8 v;
        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (281): 0 < s < secp256k1n ÷ 2 + 1, and for v in (282): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        //
        // Source OpenZeppelin
        // https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/cryptography/ECDSA.sol
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) revert InvalidSignature();
        if (v != 27 && v != 28) revert InvalidSignature();

        // Recover ECDSA signer.
        signer = ecrecover(hash_, v, r, s);

        // Prevent signer from being address(0).
        if (signer == address(0)) revert InvalidSigner();
    }
}
