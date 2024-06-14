/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Test } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { ISwapRouter } from "../../../../src/auto-compounders/slipstream/interfaces/ISwapRouter.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

contract SwapRouterFixture is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    ISwapRouter internal swapRouter;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function deploySwapRouter(address factory_, address weth9_) public {
        // Get the bytecode of the SwapRouterExtension.
        bytes memory args = abi.encode(factory_, weth9_);
        bytes memory bytecode = abi.encodePacked(vm.getCode("SwapRouter.sol"), args);

        address swapRouter_ = Utils.deployBytecode(bytecode);
        swapRouter = ISwapRouter(swapRouter_);
    }
}
