/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ExternalContracts } from "../../../lib/accounts-v2/script/utils/constants/Unichain.sol";

library Slipstream {
    address constant FACTORY = 0x31832f2a97Fd20664D76Cc421207669b55CE4BC0;
    address constant POOL_IMPLEMENTATION = 0x10499d88Bd32AF443Fc936F67DE32bE1c8Bb374C;
    address internal constant POSITION_MANAGER = ExternalContracts.SLIPSTREAM_POS_MNGR;
}

library UniswapV3 {
    address constant FACTORY = 0x1F98400000000000000000000000000000000003;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV3_POS_MNGR;
}

library UniswapV4 {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant POOL_MANAGER = 0x1F98400000000000000000000000000000000004;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV4_POS_MNGR;
}
