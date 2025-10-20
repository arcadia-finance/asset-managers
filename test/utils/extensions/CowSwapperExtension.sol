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

    function getAccount() external view returns (address) {
        return account;
    }

    function getAccountOwner() external view returns (address) {
        return accountOwner;
    }

    function getInitiator() external view returns (address) {
        return initiator;
    }

    function getSwapFee() external view returns (uint64) {
        return swapFee;
    }

    function getTokenIn() external view returns (address) {
        return tokenIn;
    }

    function getTokenOut() external view returns (address) {
        return tokenOut;
    }

    function getAmountIn() external view returns (uint256) {
        return amountIn;
    }

    function getOrderHash() external view returns (bytes32) {
        return orderHash;
    }

    function getMessageHash() external view returns (bytes32) {
        return messageHash;
    }

    function setAccount(address account_) external {
        account = account_;
    }

    function setAccountOwner(address accountOwner_) external {
        accountOwner = accountOwner_;
    }

    function setInitiator(address initiator_) external {
        initiator = initiator_;
    }

    function setSwapFee(uint64 swapFee_) external {
        swapFee = swapFee_;
    }

    function setTokenIn(address tokenIn_) external {
        tokenIn = tokenIn_;
    }

    function setTokenOut(address tokenOut_) external {
        tokenOut = tokenOut_;
    }

    function setAmountIn(uint256 amountIn_) external {
        amountIn = amountIn_;
    }

    function setOrderHash(bytes32 orderHash_) external {
        orderHash = orderHash_;
    }

    function setMessageHash(bytes32 messageHash_) external {
        messageHash = messageHash_;
    }
}
