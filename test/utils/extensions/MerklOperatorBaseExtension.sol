/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { MerklOperatorBase } from "../../../src/merkl-operator/MerklOperatorBase.sol";

contract MerklOperatorBaseExtension is MerklOperatorBase {
    constructor(address owner_, address arcadiaFactory, address merklDistributor)
        MerklOperatorBase(owner_, arcadiaFactory, merklDistributor)
    { }
}
