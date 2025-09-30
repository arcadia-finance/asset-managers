/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BalancerV2Fixture } from "../../utils/fixtures/balancer-v2/BalancerV2Fixture.f.sol";
import { CowSwapFixture } from "../../utils/fixtures/cow-swap/CowSwapFixture.f.sol";
import { CowSwapperExtension } from "../../utils/extensions/CowSwapperExtension.sol";
import { DefaultOrderHook } from "../../utils/mocks/DefaultOrderHook.sol";
import { ERC20Mock } from "../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";
import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { IERC20 } from "../../../lib/cowprotocol/src/contracts/interfaces/IERC20.sol";
import { WETH9Fixture } from "../../../lib/accounts-v2/test/utils/fixtures/weth9/WETH9Fixture.f.sol";

/**
 * @notice Common logic needed by all "CowSwapper" fuzz tests.
 */
abstract contract CowSwapper_Fuzz_Test is Fuzz_Test, BalancerV2Fixture, CowSwapFixture, WETH9Fixture {
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint64 internal constant MAX_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    struct InitiatorParams {
        uint64 swapFee;
        GPv2Order.Data order;
    }

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CowSwapperExtension internal cowSwapper;
    DefaultOrderHook internal orderHook;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, WETH9Fixture) {
        Fuzz_Test.setUp();

        // Deploy WETH9.
        WETH9Fixture.setUp();

        // Deploy Balancer Vault.
        deployBalancerVault(users.owner, address(weth9));

        // Deploy CowSwap.
        deployCowSwap(users.owner, BALANCER_VAULT);

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts(address(0));

        // Create tokens.
        token0 = new ERC20Mock("TokenA", "TOKA", 0);
        token1 = new ERC20Mock("TokenB", "TOKB", 0);
        addAssetToArcadia(address(token0), int256(1e18));
        addAssetToArcadia(address(token1), int256(1e18));

        // Deploy test contract.
        cowSwapper =
            new CowSwapperExtension(users.owner, address(factory), address(flashLoanRouter), address(hooksTrampoline));

        // Deploy mocked order hook.
        orderHook = new DefaultOrderHook();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function givenValidPrivatekey(uint256 privateKey) internal pure returns (uint256) {
        // Private key must be less than the secp256k1 curve order and != 0
        return bound(
            privateKey,
            1,
            115_792_089_237_316_195_423_570_985_008_687_907_852_837_564_279_074_904_382_605_163_141_518_161_494_337 - 1
        );
    }

    function givenValidInitiatorParams(InitiatorParams memory params) internal view {
        // Given: Swap fee is valid.
        params.swapFee = uint64(bound(params.swapFee, 0, MAX_FEE));

        // And: Order is valid.
        params.order.sellToken = IERC20(address(token0));
        params.order.buyToken = IERC20(address(token1));
        params.order.receiver = address(cowSwapper);
        params.order.sellAmount = uint96(bound(params.order.sellAmount, 1, type(uint96).max));
        params.order.buyAmount = uint96(bound(params.order.buyAmount, 1, type(uint96).max));
        params.order.validTo = uint32(bound(params.order.validTo, block.timestamp, type(uint32).max));
        params.order.feeAmount = 0;
        params.order.kind = GPv2Order.KIND_SELL;
        params.order.partiallyFillable = false;
        params.order.sellTokenBalance = GPv2Order.BALANCE_ERC20;
        params.order.buyTokenBalance = GPv2Order.BALANCE_ERC20;
    }
}
