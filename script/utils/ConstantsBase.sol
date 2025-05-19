/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

library Arcadia {
    address constant FACTORY = 0xDa14Fdd72345c4d2511357214c5B89A919768e59;
    address constant STAKED_SLIPSTREAM_AM = 0x1Dc7A0f5336F52724B650E39174cfcbbEdD67bF1;
    address constant WRAPPED_STAKED_SLIPSTREAM = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;
}

library Compounders {
    address constant SLIPSTREAM = address(0);
    address constant UNISWAP_V3 = address(0);
    address constant UNISWAP_V4 = address(0);
}

library Deployers {
    address constant ARCADIA = 0x0f518becFC14125F23b8422849f6393D59627ddB;
}

library Rebalancers {
    address constant SLIPSTREAM = address(0);
    address constant UNISWAP_V3 = address(0);
    address constant UNISWAP_V4 = address(0);
}

library Slipstream {
    address constant AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    address constant POOL_IMPLEMENTATION = 0xeC8E5342B19977B4eF8892e02D8DAEcfa1315831;
    address constant POSITION_MANAGER = 0x827922686190790b37229fd06084350E74485b72;
}

library UniswapV3 {
    address constant FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
}

library UniswapV4 {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address constant WETH = 0x4200000000000000000000000000000000000006;
}

library YieldClaimers {
    address constant SLIPSTREAM = address(0);
    address constant UNISWAP_V3 = address(0);
    address constant UNISWAP_V4 = address(0);
}
