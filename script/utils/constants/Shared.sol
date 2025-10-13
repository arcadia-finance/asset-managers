/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ArcadiaAccounts, AssetModules } from "../../../lib/accounts-v2/script/utils/constants/Shared.sol";

library ArcadiaAssetManagers {
    address constant FACTORY = ArcadiaAccounts.FACTORY;
    address constant STAKED_SLIPSTREAM_AM = AssetModules.STAKED_SLIPSTREAM;
    address constant WRAPPED_STAKED_SLIPSTREAM = 0xD74339e0F10fcE96894916B93E5Cc7dE89C98272;
}

library Compounders {
    address constant SLIPSTREAM = 0x4694c34d153EE777CC07d01AC433bcC010A20EBd;
    address constant UNISWAP_V3 = 0x80D3548bc54710d46201D554712E8638fD51326D;
    address constant UNISWAP_V4 = 0xCfF15E24a453aFAd454533E6D10889A84e2A68e1;
}

library Helpers {
    address constant ROUTER_TRAMPOLINE = 0x354dBBa1348985CC952c467b8ddaF5dD07590667;
}

library Rebalancers {
    address constant SLIPSTREAM = 0xEfe600366e9847D405f2238cF9196E33780B3A42;
    address constant UNISWAP_V3 = 0xD8285fC23eFF687B8b618b78d85052f1eD17236E;
    address constant UNISWAP_V4 = 0xa8676C8c197E12a71AE82a08B02DD9e666312cF1;
}

library YieldClaimers {
    address constant SLIPSTREAM = 0x1f75aBF8a24782053B351D9b4EA6d1236ED59105;
    address constant UNISWAP_V3 = 0x40462e71Effd9974Fee04B6b327B701D663f753e;
    address constant UNISWAP_V4 = 0x3BC2B398eEEE9807ff76fdb4E11526dE0Ee80cEa;
}

library SafesAssetManagers {
    address internal constant GUARDIAN = 0x8546d2a8e0c3C6658e8796FF2Ed3c78A5238c527;
}
