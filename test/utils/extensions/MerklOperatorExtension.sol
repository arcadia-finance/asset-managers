/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { MerklOperator } from "../../../src/merkl-operator/MerklOperator.sol";

contract MerklOperatorExtension is MerklOperator {
    constructor(address owner_, address arcadiaFactory, address merklDistributor)
        MerklOperator(owner_, arcadiaFactory, merklDistributor)
    { }
}
