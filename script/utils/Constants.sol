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
    address constant UNISWAP_V3 = address(0x04Ecd9B27C2ab7bC26984135e0f6E82F7ff5014D);
}

library Parameters {
    uint256 constant COMPOUND_THRESHOLD = 5 * 1e18; // 5 USD
    uint256 constant INITIATOR_SHARE = 0.01 * 1e18; // 1%
    uint256 constant TOLERANCE = 0.005 * 1e18; // 0.5%
}
