/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { OrderHook } from "../../../src/cow-swapper/periphery/OrderHook.sol";

contract DefaultOrderHook is OrderHook {
    /* //////////////////////////////////////////////////////////////
                               STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from an Arcadia Account to a struct with Account-specific information.
    mapping(address cowSwapper => mapping(address account => AccountInfo)) public accountInfo;

    // A struct containing Account-specific strategy information.
    struct AccountInfo {
        // A bytes array containing custom strategy information.
        bytes customInfo;
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the CoW Swapper to set the Account specific information.
     * @param account The contract address of the Arcadia Account to set the rebalance info for.
     * @param hookData Encoded data containing hook specific parameters.
     */
    function setHook(address account, bytes calldata hookData) external override {
        (bytes memory customInfo) = abi.decode(hookData, (bytes));

        accountInfo[msg.sender][account] = AccountInfo({ customInfo: customInfo });
    }

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called before the swap is executed.
     * param account The contract address of the Arcadia Account.
     * @param order The CoW Swap order.
     * @return Bool indicating if the order is valid.
     */
    function isValidOrder(address, GPv2Order.Data memory order) external view override returns (bool) {
        if (order.receiver != msg.sender) return false;
        if (order.feeAmount > 0) return false;
        if (order.kind != GPv2Order.KIND_SELL) return false;
        if (order.partiallyFillable) return false;
        if (order.sellTokenBalance != GPv2Order.BALANCE_ERC20) return false;
        if (order.buyTokenBalance != GPv2Order.BALANCE_ERC20) return false;

        return true;
    }
}
