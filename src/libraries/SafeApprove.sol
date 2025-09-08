/**
 * https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.0;

import { ERC20 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";

library SafeApprove {
    /**
     * @notice Approves an amount of token for a spender.
     * @param token The contract address of the token being approved.
     * @param to The spender.
     * @param amount the amount of token being approved.
     * @dev Copied from Solady safeApproveWithRetry (MIT): https://github.com/Vectorized/solady/blob/main/src/utils/SafeTransferLib.sol
     * @dev Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract.
     * If the initial attempt to approve fails, attempts to reset the approved amount to zero,
     * then retries the approval again (some tokens, e.g. USDT, requires this).
     * Reverts upon failure.
     */
    function safeApproveWithRetry(ERC20 token, address to, uint256 amount) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x14, to) // Store the `to` argument.
            mstore(0x34, amount) // Store the `amount` argument.
            mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
            // Perform the approval, retrying upon failure.
            if iszero(
                and( // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                )
            ) {
                mstore(0x34, 0) // Store 0 for the `amount`.
                mstore(0x00, 0x095ea7b3000000000000000000000000) // `approve(address,uint256)`.
                pop(call(gas(), token, 0, 0x10, 0x44, codesize(), 0x00)) // Reset the approval.
                mstore(0x34, amount) // Store back the original `amount`.
                // Retry the approval, reverting upon failure.
                if iszero(
                    and(
                        or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                        call(gas(), token, 0, 0x10, 0x44, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0x3e3f8f73) // `ApproveFailed()`.
                    revert(0x1c, 0x04)
                }
            }
            mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
        }
    }
}
