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

    function getAccount() public view returns (address) {
        return account;
    }

    function getInitiator() public view returns (address) {
        return initiator;
    }

    function getSwapFee() public view returns (uint64) {
        return swapFee;
    }

    function getTokenIn() public view returns (address) {
        return tokenIn;
    }

    function getTokenOut() public view returns (address) {
        return tokenOut;
    }

    function getAmountIn() public view returns (uint256) {
        return amountIn;
    }

    function getAmountOut() public view returns (uint256) {
        return amountOut;
    }

    function getOrderHash() public view returns (bytes32) {
        return orderHash;
    }

    function getMessageHash() public view returns (bytes32) {
        return messageHash;
    }

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

    function setMessageHash(bytes32 messageHash_) public {
        messageHash = messageHash_;
    }
}
