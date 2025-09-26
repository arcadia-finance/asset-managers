/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.0;

import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";

interface IOrderHook {
    function setHook(address account, bytes calldata hookData) external;
    function isValidOrder(address account, GPv2Order.Data memory order) external view returns (bool);
}
