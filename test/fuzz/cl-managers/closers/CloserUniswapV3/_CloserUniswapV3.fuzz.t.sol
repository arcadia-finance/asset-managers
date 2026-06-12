/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CloserUniswapV3Extension } from "../../../../utils/extensions/CloserUniswapV3Extension.sol";
import { Constants } from "../../../../../lib/accounts-v2/test/utils/Constants.sol";
import { UniswapV3_Fuzz_Test } from "../../base/UniswapV3/_UniswapV3.fuzz.t.sol";
import { Utils } from "../../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "CloserUniswapV3" fuzz tests.
 */
abstract contract CloserUniswapV3_Fuzz_Test is UniswapV3_Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_CLAIM_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CloserUniswapV3Extension internal closer;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(UniswapV3_Fuzz_Test) {
        UniswapV3_Fuzz_Test.setUp();

        // Deploy test contract.
        closer = new CloserUniswapV3Extension(
            users.owner, address(factory), address(nonfungiblePositionManager), address(uniswapV3Factory)
        );

        // Overwrite code hash of the UniswapV3Pool.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytecode = address(closer).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, Constants.POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Store overwritten bytecode.
        vm.etch(address(closer), bytecode);
    }
}
