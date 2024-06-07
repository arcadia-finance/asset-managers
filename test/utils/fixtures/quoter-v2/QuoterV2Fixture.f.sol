/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Test } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { IQuoter } from "../../../../src/auto-compounder/interfaces/IQuoter.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

contract QuoterV2Fixture is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    IQuoter internal quoter;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function deployQuoterV2(address factoryV3_, address weth9_) public {
        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);

        // Get the bytecode of the Quoter.
        args = abi.encode(factoryV3_, weth9_);
        bytecode = abi.encodePacked(vm.getCode("QuoterV2.sol"), args);

        // Overwrite constant in bytecode of Quoter.
        // -> Replace the code hash of UniswapV3Pool.sol with the code hash of UniswapV3PoolExtension.sol
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        address quoter_ = Utils.deployBytecode(bytecode);
        quoter = IQuoter(quoter_);
    }
}
