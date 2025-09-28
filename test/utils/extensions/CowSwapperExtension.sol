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
}
