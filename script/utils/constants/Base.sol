/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ExternalContracts } from "../../../lib/accounts-v2/script/utils/constants/Base.sol";

library SafesAssetManagers {
    address internal constant GUARDIAN = 0x8546d2a8e0c3C6658e8796FF2Ed3c78A5238c527;
}

library Slipstream {
    address internal constant FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address internal constant POOL_IMPLEMENTATION = 0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831;
    address internal constant POSITION_MANAGER = ExternalContracts.SLIPSTREAM_POS_MNGR;
}

library UniswapV3 {
    address internal constant FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV3_POS_MNGR;
}

library UniswapV4 {
    address internal constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV4_POS_MNGR;
}
