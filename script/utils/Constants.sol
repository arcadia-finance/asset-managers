/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

library Compounders {
    address constant ALIEN_BASE = address(0x15E755f17E3712F561d25538cCc0488445398c8D);
    address payable constant SLIPSTREAM = payable(address(0xccc601cFd309894ED7B8F15Cb35057E5A6a18B79));
    address constant UNISWAP_V3 = address(0x351a4CE4C45029D847F396132953673BcdEAF324);
}

library CompoundersSpot {
    address constant ALIEN_BASE = address(0x45c1661EF92CF0310A62cEc0cFb7BA690E9C6837);
    address payable constant SLIPSTREAM = payable(address(0x5593957003f1C40287D23A76EcBD6c503B413a64));
    address constant UNISWAP_V3 = address(0x2b0bb37203b850Ee73f19b735C92c18631291210);
}

library CompounderHelpers {
    address constant ALIEN_BASE = address(0x8363503aD282d4D0B3742Befdce5b425c60F77E7);
    address constant SLIPSTREAM = address(0xAAAAA15c3E04E7a827aD60Ae0544588BfdaeBa61);
    address constant SLIPSTREAM_V2 = address(0x8A44c068e90dDFf752dAd22E07BE2B71e5a98e11);
    address constant UNISWAP_V3 = address(0x04Ecd9B27C2ab7bC26984135e0f6E82F7ff5014D);
    address constant UNISWAP_V3_V2 = address(0x58bc2000e0a3a8094C397B43e8621EF5dbA280e7);
}

library CompounderParameters {
    uint256 constant COMPOUND_THRESHOLD = 5 * 1e18; // 5 USD
    uint256 constant INITIATOR_SHARE = 0.01 * 1e18; // 1%
    uint256 constant TOLERANCE = 0.005 * 1e18; // 0.5%
}

library Quoters {
    address constant ALIEN_BASE = address(0x2ba1d35920DB74a1dB97679BC27d2cBa81bB96ea);
    address constant SLIPSTREAM = address(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0);
    address constant UNISWAP_V3 = address(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);
}

library Rebalancers {
    address constant Margin_V1 = address(0x8ce0aB0fa8dB672e898c51248166C0ac8d55381A);
    address constant Margin_V2 = address(0x9Ba13B512004A5d5Dc9DdA232215797cC1672597);
    address constant Spot_V1 = address(0x5E45a9dAb20aA51b8B6c3cb39a934c3e845f29E6);
}

library RebalancerParameters {
    uint256 constant MAX_TOLERANCE = 0.01 * 1e18; // 1%
    uint256 constant MAX_INITIATOR_FEE = 0.2 * 1e18; // 20%
    uint256 constant MIN_LIQUIDITY_RATIO = 0.98 * 1e18; // 98%
}
