/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

library Slipstream {
    address constant FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address constant POOL_IMPLEMENTATION = 0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831;
}

library UniswapV3 {
    address constant FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
}

library UniswapV4 {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
}
