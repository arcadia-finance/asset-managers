/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.30;

import { ERC20, SafeTransferLib } from "../../lib/accounts-v2/lib/solmate/src/utils/SafeTransferLib.sol";
import { ReentrancyGuard } from "../../lib/accounts-v2/lib/solmate/src/utils/ReentrancyGuard.sol";
import { SafeApprove } from "../libraries/SafeApprove.sol";

/**
 * @title Trampoline to forward calls to routers.
 * @author Pragma Labs
 */
contract RouterTrampoline is ReentrancyGuard {
    using SafeApprove for ERC20;
    using SafeTransferLib for ERC20;

    /* ///////////////////////////////////////////////////////////////
                                LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Forwards a swap via an arbitrary router.
     * @param router The contract address of the router.
     * @param callData The calldata for the swap.
     * @param tokenIn The contract address of the token to swap from.
     * @param tokenOut The contract address of the token to swap to.
     * @param amountIn The maximum amount of tokenIn to swap.
     * @return balanceIn The balance of tokenIn after the swap.
     * @return balanceOut The balance of tokenOut after the swap.
     * @dev TokenIn must be send to the RouterTrampoline before the swap.
     */
    function execute(address router, bytes calldata callData, address tokenIn, address tokenOut, uint256 amountIn)
        external
        nonReentrant
        returns (uint256 balanceIn, uint256 balanceOut)
    {
        // Approve tokenIn to swap.
        ERC20(tokenIn).safeApproveWithRetry(router, amountIn);

        // Execute swap.
        (bool success, bytes memory result) = router.call(callData);
        require(success, string(result));

        // Transfer the tokens back to the caller.
        balanceIn = ERC20(tokenIn).balanceOf(address(this));
        balanceOut = ERC20(tokenOut).balanceOf(address(this));
        if (balanceIn > 0) ERC20(tokenIn).safeTransfer(msg.sender, balanceIn);
        if (balanceOut > 0) ERC20(tokenOut).safeTransfer(msg.sender, balanceOut);
    }
}
