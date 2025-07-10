/**
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.26;

import { CowSwapperHooks } from "../CowSwapperHooks.sol";

/**
 * @notice .
 */
library AppData {
    function getAppDataJSON(address target, address account_) internal pure returns (bytes memory appDataJSON) {
        appDataJSON = bytes.concat(
            '{"version":"1.3.0",' '"appCode":"cow-swapper-hooks-v0.0.1",' '"metadata":' '{"hooks":'
            '{"version":"1.3.0",' '"pre":[{"target":"',
            abi.encodePacked(target),
            '","callData":"',
            abi.encodeWithSelector(CowSwapperHooks.beforeSwap.selector, account_),
            '",' '"gasLimit":"1500000"}], post:[{"target":"',
            abi.encodePacked(target),
            '","callData":"',
            abi.encodeWithSelector(CowSwapperHooks.afterSwap.selector, account_),
            '",' '"gasLimit":"1500000"}]}}}'
        );
    }
}
