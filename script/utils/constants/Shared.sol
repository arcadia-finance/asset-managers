/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ArcadiaAccounts, AssetModules } from "../../../lib/accounts-v2/script/utils/constants/Shared.sol";

library ArcadiaAssetManagers {
    address constant FACTORY = ArcadiaAccounts.FACTORY;
    address constant STAKED_SLIPSTREAM_AM = AssetModules.STAKED_SLIPSTREAM;
    address constant WRAPPED_STAKED_SLIPSTREAM = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;
}

library Compounders {
    address constant SLIPSTREAM = 0x57FAA0BC4C045818d46055001702ad88a704A893;
    address constant UNISWAP_V3 = 0xaaC2DdDA7B72d76dc1EdDd869Fa5933f9AAb501e;
    address constant UNISWAP_V4 = 0xc89aaAD8Fc7Be29C461Aef085b2f72269dE69c16;
}

library Helpers {
    address constant ROUTER_TRAMPOLINE = address(0);
}

library Rebalancers {
    address constant SLIPSTREAM = 0xB20a0D866CC096C334FDF4A43cFc54a580735994;
    address constant UNISWAP_V3 = 0xB2Dc74DC75B5dECE7cD8Eb7dCF00224F3fD4B26d;
    address constant UNISWAP_V4 = 0xcF2e1Fe1c81f9Ab6869913bd5518e9461B79af4a;
}

library YieldClaimers {
    address constant SLIPSTREAM = 0x2a07d99eC1140e25DB07283930160d4BDE93d09f;
    address constant UNISWAP_V3 = 0xc5815c102F0F1D7030E942d993f0BF44fEE66235;
    address constant UNISWAP_V4 = 0x2eD3Db522944F5F68A2EBc3692d865D2aA2bA34E;
}
