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
    address constant SLIPSTREAM = 0x4694c34d153ee777cc07d01ac433bcc010a20ebd;
    address constant UNISWAP_V3 = 0x80d3548bc54710d46201d554712e8638fd51326d;
    address constant UNISWAP_V4 = 0xcff15e24a453afad454533e6d10889a84e2a68e1;
}

library Helpers {
    address constant ROUTER_TRAMPOLINE = 0x354dbba1348985cc952c467b8ddaf5dd07590667;
}

library Rebalancers {
    address constant SLIPSTREAM = 0xefe600366e9847d405f2238cf9196e33780b3a42;
    address constant UNISWAP_V3 = 0xd8285fc23eff687b8b618b78d85052f1ed17236e;
    address constant UNISWAP_V4 = 0xa8676c8c197e12a71ae82a08b02dd9e666312cf1;
}

library YieldClaimers {
    address constant SLIPSTREAM = 0x1f75abf8a24782053b351d9b4ea6d1236ed59105;
    address constant UNISWAP_V3 = 0x40462e71effd9974fee04b6b327b701d663f753e;
    address constant UNISWAP_V4 = 0x3bc2b398eeee9807ff76fdb4e11526de0ee80cea;
}
