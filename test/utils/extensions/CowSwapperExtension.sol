/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CowSwapper } from "../../../src/cow-swapper/CowSwapper.sol";

contract CowSwapperExtension is CowSwapper {
    constructor(address owner_, address arcadiaFactory, address flashLoanRouter, address hooksTrampoline)
        CowSwapper(owner_, arcadiaFactory, flashLoanRouter, hooksTrampoline)
    { }

    function setAccount(address account_) public {
        account = account_;
    }

    function setInitiator(address initiator_) public {
        initiator = initiator_;
    }

    function setSwapFee(uint64 swapFee_) public {
        swapFee = swapFee_;
    }

    function setTokenIn(address tokenIn_) public {
        tokenIn = tokenIn_;
    }

    function setTokenOut(address tokenOut_) public {
        tokenOut = tokenOut_;
    }

    function setAmountIn(uint256 amountIn_) public {
        amountIn = amountIn_;
    }

    function setAmountOut(uint256 amountOut_) public {
        amountOut = amountOut_;
    }

    function setOrderHash(bytes32 orderHash_) public {
        orderHash = orderHash_;
    }
}
