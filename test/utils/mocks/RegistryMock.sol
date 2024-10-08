/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

contract RegistryMock {
    function isAllowed(address, uint256) external pure returns (bool) {
        return true;
    }
}
