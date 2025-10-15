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
    address constant SLIPSTREAM = 0x467837f44A71e3eAB90AEcfC995c84DC6B3cfCF7;
    address constant UNISWAP_V3 = 0x02e1fa043214E51eDf1F0478c6D0d3D5658a2DC3;
    address constant UNISWAP_V4 = 0xAA95c9c402b195D8690eCaea2341a76e3266B189;
}

library Helpers {
    address constant ROUTER_TRAMPOLINE = 0x354dBBa1348985CC952c467b8ddaF5dD07590667;
}

library MerklOperators {
    address constant BASE = 0x4aa34F76F85F72A0F0B6Df7aE109F94Da0575d5F;
    address constant SHARED = 0x969F0251360b9Cf11c68f6Ce9587924c1B8b42C6;
}

library Rebalancers {
    address constant SLIPSTREAM = 0xE07A9383AF8E0B1320419dFeF205bb9bA75f3Ef2;
    address constant UNISWAP_V3 = 0xbb22cdbfFF5a263E85917803692db3630bF860c4;
    address constant UNISWAP_V4 = 0x9E466179c46eB098B564cbE319bA4b3EAd6476C1;
}

library YieldClaimers {
    address constant SLIPSTREAM = 0x5a8278D37b7a787574b6Aa7E18d8C02D994f18Ba;
    address constant UNISWAP_V3 = 0x75Ed28EA8601Ce9F5FbcAB1c2428f04A57aFaA16;
    address constant UNISWAP_V4 = 0xD8aa21AB7f9B8601CB7d7A776D3AFA1602d5D8D4;
}

library SafesAssetManagers {
    address internal constant GUARDIAN = 0x8546d2a8e0c3C6658e8796FF2Ed3c78A5238c527;
}
