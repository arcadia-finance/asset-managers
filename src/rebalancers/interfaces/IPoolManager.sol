// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.22;

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
}
