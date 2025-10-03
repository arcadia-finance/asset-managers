/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { DefaultOrderHook } from "../../../src/cow-swapper/periphery/DefaultOrderHook.sol";

contract DefaultOrderHookExtension is DefaultOrderHook {
    constructor(address cowSwapper) DefaultOrderHook(cowSwapper) { }

    function decodeInitiatorData(bytes calldata initiatorData)
        external
        pure
        returns (address tokenOut, uint112 amountOut, uint32 validTo, uint64 swapFee)
    {
        return _decodeInitiatorData(initiatorData);
    }

    function getCowSwapperHexString() external view returns (string memory) {
        return COW_SWAPPER_HEX_STRING;
    }
}
