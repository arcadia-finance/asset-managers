/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

library Compounders {
    address constant ALIEN_BASE = address(0);
    address payable constant SLIPSTREAM = payable(address(0xccc601cFd309894ED7B8F15Cb35057E5A6a18B79));
    address constant UNISWAP_V3 = address(0x351a4CE4C45029D847F396132953673BcdEAF324);
}

library CompounderHelpers {
    address constant ALIEN_BASE = address(0);
    address constant SLIPSTREAM = address(0xAAAAA15c3E04E7a827aD60Ae0544588BfdaeBa61);
    address constant SLIPSTREAM_V2 = address(0);
    address constant UNISWAP_V3 = address(0x04Ecd9B27C2ab7bC26984135e0f6E82F7ff5014D);
    address constant UNISWAP_V3_V2 = address(0);
}

library Parameters {
    uint256 constant COMPOUND_THRESHOLD = 5 * 1e18; // 5 USD
    uint256 constant INITIATOR_SHARE = 0.01 * 1e18; // 1%
    uint256 constant TOLERANCE = 0.005 * 1e18; // 0.5%
}

library Quoters {
    address constant ALIEN_BASE = address(0x2ba1d35920DB74a1dB97679BC27d2cBa81bB96ea);
    address constant SLIPSTREAM = address(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0);
    address constant UNISWAP_V3 = address(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);
}
