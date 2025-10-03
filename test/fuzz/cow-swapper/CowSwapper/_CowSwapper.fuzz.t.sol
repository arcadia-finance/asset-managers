/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BalancerV2Fixture } from "../../../utils/fixtures/balancer-v2/BalancerV2Fixture.f.sol";
import { CowSwapFixture } from "../../../utils/fixtures/cow-swap/CowSwapFixture.f.sol";
import { CowSwapperExtension } from "../../../utils/extensions/CowSwapperExtension.sol";
import { DefaultOrderHook } from "../../../../src/cow-swapper/periphery/DefaultOrderHook.sol";
import { ERC20Mock } from "../../../../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { GPv2Order } from "../../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { HooksTrampoline } from "../../../utils/mocks/HooksTrampoline.sol";
import { ICowSettlement } from "../../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { IERC20 } from "../../../../lib/cowprotocol/src/contracts/interfaces/IERC20.sol";
import { Loan } from "../../../../lib/flash-loan-router/src/library/Loan.sol";
import { LoansWithSettlement } from "../../../../lib/flash-loan-router/src/library/LoansWithSettlement.sol";
import { RouterMock } from "../../../../lib/accounts-v2/test/utils/mocks/action-targets/RouterMock.sol";
import { WETH9Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/weth9/WETH9Fixture.f.sol";

/**
 * @notice Common logic needed by all "CowSwapper" fuzz tests.
 */
abstract contract CowSwapper_Fuzz_Test is Fuzz_Test, BalancerV2Fixture, CowSwapFixture, WETH9Fixture {
    using GPv2Order for GPv2Order.Data;
    using LoansWithSettlement for bytes;
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */

    uint64 internal constant MAX_FEE = 0.01 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    RouterMock internal routerMock;

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
        orderHook = new DefaultOrderHook(address(cowSwapper));

        // Deploy mocked router.
        routerMock = new RouterMock();
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

    function givenValidOrder(uint64 swapFee, GPv2Order.Data memory order) internal view {
        order.sellToken = IERC20(address(token0));
        order.buyToken = IERC20(address(token1));
        order.receiver = address(cowSwapper);
        order.sellAmount = uint96(bound(order.sellAmount, 1, type(uint96).max));
        order.buyAmount = uint96(bound(order.buyAmount, 1, type(uint96).max));
        order.validTo = uint32(bound(order.validTo, block.timestamp, type(uint32).max));
        order.feeAmount = 0;
        order.kind = GPv2Order.KIND_SELL;
        order.partiallyFillable = false;
        order.sellTokenBalance = GPv2Order.BALANCE_ERC20;
        order.buyTokenBalance = GPv2Order.BALANCE_ERC20;

        order.appData = getAppDataHash(swapFee, order);
    }

    function getAppDataHash(uint64 swapFee, GPv2Order.Data memory order) internal view returns (bytes32 appDataHash) {
        bytes memory initiatorData = abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee);
        bytes memory beforeSwapCallData = abi.encodeCall(cowSwapper.beforeSwap, (initiatorData));

        appDataHash =
            orderHook.getAppDataHash(address(account), address(order.sellToken), order.sellAmount, beforeSwapCallData);
    }

    function setCowSwapper(address initiator) internal {
        // Given: Cow Swapper is set a s Asset Manager.
        address[] memory assetManagers = new address[](1);
        assetManagers[0] = address(cowSwapper);
        bool[] memory statuses = new bool[](1);
        statuses[0] = true;
        bytes[] memory datas = new bytes[](1);
        datas[0] = bytes("");
        vm.prank(account.owner());
        account.setAssetManagers(assetManagers, statuses, datas);

        // And: Initiator is set on Cow Swapper.
        vm.prank(account.owner());
        cowSwapper.setAccountInfo(address(account), initiator, MAX_FEE, address(orderHook), abi.encode(""), "");
    }

    function getSettlementCallData(uint64 swapFee, GPv2Order.Data memory order, bytes memory signature)
        internal
        view
        returns (bytes memory settlementCallData)
    {
        settlementCallData = getSettlementCallData(swapFee, order, signature, order.buyAmount, order.buyAmount);
    }

    function getSettlementCallData(
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes memory signature,
        uint256 buyClearingPrice,
        uint256 buyAmount
    ) internal view returns (bytes memory settlementCallData) {
        (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            ICowSettlement.Trade[] memory trades,
            ICowSettlement.Interaction[][3] memory interactions
        ) = getSettlementData(swapFee, order, signature, buyClearingPrice, buyAmount);

        settlementCallData = abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));
    }

    function getSettlementData(uint64 swapFee, GPv2Order.Data memory order, bytes memory signature)
        internal
        view
        returns (
            address[] memory,
            uint256[] memory,
            ICowSettlement.Trade[] memory,
            ICowSettlement.Interaction[][3] memory
        )
    {
        return getSettlementData(swapFee, order, signature, order.buyAmount, order.buyAmount);
    }

    function getSettlementData(
        uint64 swapFee,
        GPv2Order.Data memory order,
        bytes memory signature,
        uint256 buyClearingPrice,
        uint256 buyAmount
    )
        internal
        view
        returns (
            address[] memory tokens,
            uint256[] memory clearingPrices,
            ICowSettlement.Trade[] memory trades,
            ICowSettlement.Interaction[][3] memory interactions
        )
    {
        tokens = new address[](2);
        tokens[0] = address(order.sellToken);
        tokens[1] = address(order.buyToken);

        clearingPrices = new uint256[](2);
        clearingPrices[0] = buyClearingPrice;
        clearingPrices[1] = order.sellAmount;

        trades = new ICowSettlement.Trade[](1);
        trades[0] = ICowSettlement.Trade(
            0,
            1,
            order.receiver,
            order.sellAmount,
            order.buyAmount,
            order.validTo,
            order.appData,
            order.feeAmount,
            packFlags(),
            order.sellAmount,
            signature
        );

        // Pre swap interactions.
        interactions[0] = new ICowSettlement.Interaction[](2);
        // Driver interaction.
        interactions[0][0] = ICowSettlement.Interaction({
            target: address(cowSwapper),
            value: 0,
            callData: abi.encodeWithSignature(
                "approve(address,address,uint256)", address(order.sellToken), address(vaultRelayer), order.sellAmount
            )
        });

        // And: BeforeSwap is called in pre swap hook.
        {
            HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
            bytes memory initiatorData =
                abi.encodePacked(order.buyToken, uint112(order.buyAmount), order.validTo, swapFee);
            hooks[0] = HooksTrampoline.Hook({
                target: address(cowSwapper),
                callData: abi.encodeCall(cowSwapper.beforeSwap, (initiatorData)),
                gasLimit: 80_000
            });
            interactions[0][1] = ICowSettlement.Interaction({
                target: address(hooksTrampoline),
                value: 0,
                callData: abi.encodeCall(hooksTrampoline.execute, (hooks))
            });
        }

        // Swap interactions.
        interactions[1] = new ICowSettlement.Interaction[](2);
        interactions[1][0] = ICowSettlement.Interaction({
            target: address(order.sellToken),
            value: 0,
            callData: abi.encodeCall(token0.approve, (address(routerMock), order.sellAmount))
        });
        interactions[1][1] = ICowSettlement.Interaction({
            target: address(routerMock),
            value: 0,
            callData: abi.encodeCall(
                routerMock.swapAssets, (address(order.sellToken), address(order.buyToken), order.sellAmount, buyAmount)
            )
        });

        // No Post Swap interactions.
    }

    function getLoansWithSettlement(Loan.Data[] calldata loans, bytes calldata settlementCallData)
        public
        pure
        returns (bytes memory)
    {
        return LoansWithSettlement.encode(loans, settlementCallData);
    }

    function packFlags() internal pure returns (uint256) {
        // For information on flag encoding, see:
        // https://github.com/cowprotocol/contracts/blob/v1.0.0/src/contracts/libraries/GPv2Trade.sol#L70-L93
        uint256 sellOrderFlag = 0;
        uint256 fillOrKillFlag = 0 << 1;
        uint256 internalSellTokenBalanceFlag = 0 << 2;
        uint256 internalBuyTokenBalanceFlag = 0 << 4;
        uint256 eip1271Flag = 2 << 5;
        return sellOrderFlag | fillOrKillFlag | internalSellTokenBalanceFlag | internalBuyTokenBalanceFlag | eip1271Flag;
    }

    function getSignature(address account_, uint256 swapFee, GPv2Order.Data memory order, uint256 privateKey)
        public
        view
        returns (bytes memory sig)
    {
        bytes32 messageHash = keccak256(abi.encode(account_, swapFee, order.hash(orderHook.DOMAIN_SEPARATOR())));
        sig = getSignature(messageHash, privateKey);
    }

    function getSignature(bytes32 messageHash, uint256 privateKey) public pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
