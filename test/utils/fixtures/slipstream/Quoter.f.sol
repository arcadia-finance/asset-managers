/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Test } from "../../../../lib/accounts-v2/lib/forge-std/src/Test.sol";
import { IQuoter } from "../../../../src/auto-compounder/interfaces/Slipstream/IQuoter.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

contract QuoterFixture is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    IQuoter internal quoterCL;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function deployQuoter(address factory_, address weth9_) public {
        // Get the bytecode of the Quoter.
        bytes memory args = abi.encode(factory_, weth9_);
        bytes memory bytecode = abi.encodePacked(vm.getCode("SlipstreamQuoterV2Extension.sol"), args);

        address quoter_ = Utils.deployBytecode(bytecode);
        quoterCL = IQuoter(quoter_);
    }
}
