/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

library Compounders {
    address payable constant SLIPSTREAM = payable(address(0xbD7C9CB70D8E60C200c12d9948e1999391983F17));
    address constant UNISWAP_V3 = address(0x00405c77a1C9e728bDAaAe1407022C9C2334F7C1);
}

library CompounderHelpers {
    address constant SLIPSTREAM = address(0xc8b3fe522e63671B4E1E43329b2d71Db89D4d653);
    address constant UNISWAP_V3 = address(0x57Ec4F66a380b8f53D99c55D42c9B71FeB14FA15);
}

library Parameters {
    uint256 constant COMPOUND_THRESHOLD = 5 * 1e18; // 5 USD
    uint256 constant INITIATOR_SHARE = 0.01 * 1e18; // 1%
    uint256 constant TOLERANCE = 0.005 * 1e18; // 0.5%
}
