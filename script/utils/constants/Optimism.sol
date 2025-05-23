/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { ExternalContracts } from "../../../lib/accounts-v2/script/utils/constants/Optimism.sol";

library Slipstream {
    address constant FACTORY = 0xCc0bDDB707055e04e497aB22a59c2aF4391cd12F;
    address constant POOL_IMPLEMENTATION = 0xc28aD28853A547556780BEBF7847628501A3bCbb;
    address internal constant POSITION_MANAGER = ExternalContracts.SLIPSTREAM_POS_MNGR;
}

library UniswapV3 {
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV3_POS_MNGR;
}

library UniswapV4 {
    address constant PERMIT_2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant POOL_MANAGER = 0x9a13F98Cb987694C9F086b1F5eB990EeA8264Ec3;
    address internal constant POSITION_MANAGER = ExternalContracts.UNISWAPV4_POS_MNGR;
}
