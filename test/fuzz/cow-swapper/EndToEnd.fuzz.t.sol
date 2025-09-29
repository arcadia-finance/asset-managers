/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Borrower } from "../../../lib/flash-loan-router/src/mixin/Borrower.sol";
import { CowSwapper_Fuzz_Test } from "./_CowSwapper.fuzz.t.sol";
import { GPv2Order } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { HooksTrampoline } from "../../utils/mocks/HooksTrampoline.sol";
import { IBorrower } from "../../../lib/flash-loan-router/src/interface/IBorrower.sol";
import { ICowSettlement } from "../../../lib/flash-loan-router/src/interface/ICowSettlement.sol";
import { IERC20 } from "../../../lib/flash-loan-router/src/vendored/IERC20.sol";
import { Loan } from "../../../lib/flash-loan-router/src/library/Loan.sol";
import { RouterMock } from "../../../lib/accounts-v2/test/utils/mocks/action-targets/RouterMock.sol";

/**
 * @notice Fuzz tests for the function full "flashLoanAndSettle" flow of contract "CowSwapper".
 */
contract EndToEnd_CowSwapper_Fuzz_Test is CowSwapper_Fuzz_Test {
    using GPv2Order for GPv2Order.Data;
    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    RouterMock internal routerMock;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        CowSwapper_Fuzz_Test.setUp();

        routerMock = new RouterMock();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Success_EndToEnd(uint256 initiatorPrivateKey, uint96 amountIn, uint96 amountOut, uint64 swapFee)
        public
    {
        // Given: An initiator is set.
        // Private key must be less than the secp256k1 curve order and != 0
        initiatorPrivateKey = bound(
            initiatorPrivateKey,
            1,
            115_792_089_237_316_195_423_570_985_008_687_907_852_837_564_279_074_904_382_605_163_141_518_161_494_337 - 1
        );
        amountIn = uint96(bound(amountIn, 1, type(uint96).max));
        amountOut = uint96(bound(amountOut, 1, type(uint96).max));
        swapFee = uint64(bound(swapFee, 0, MAX_FEE));

        {
            address[] memory assetManagers = new address[](1);
            assetManagers[0] = address(cowSwapper);
            bool[] memory statuses = new bool[](1);
            statuses[0] = true;
            bytes[] memory datas = new bytes[](1);
            datas[0] = bytes("");
            vm.prank(users.accountOwner);
            account.setAssetManagers(assetManagers, statuses, datas);
        }
        vm.prank(users.accountOwner);
        cowSwapper.setAccountInfo(
            address(account), vm.addr(initiatorPrivateKey), MAX_FEE, address(orderHook), abi.encode(""), ""
        );

        // Flashloan definition
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = Loan.Data({
            amount: amountIn,
            borrower: IBorrower(address(cowSwapper)),
            lender: address(account),
            token: IERC20(address(token0))
        });

        ICowSettlement.Interaction[][3] memory interactions;
        {
            ICowSettlement.Interaction[] memory preInteractions = new ICowSettlement.Interaction[](2);
            ICowSettlement.Interaction[] memory swapInteractions = new ICowSettlement.Interaction[](2);
            ICowSettlement.Interaction[] memory postInteractions = new ICowSettlement.Interaction[](0);
            interactions = [preInteractions, swapInteractions, postInteractions];
        }

        interactions[0][0] = ICowSettlement.Interaction({
            target: address(cowSwapper),
            value: 0,
            callData: abi.encodeCall(Borrower.approve, (IERC20(address(token0)), address(vaultRelayer), amountIn))
        });

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: token0_,
            buyToken: token1_,
            receiver: address(cowSwapper),
            sellAmount: amountIn,
            buyAmount: amountOut,
            validTo: type(uint32).max,
            appData: bytes32(0),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        {
            bytes memory signature = getSignature(address(account), swapFee, order, initiatorPrivateKey);
            HooksTrampoline.Hook[] memory hooks = new HooksTrampoline.Hook[](1);
            hooks[0] = HooksTrampoline.Hook({
                target: address(cowSwapper),
                callData: abi.encodeCall(cowSwapper.beforeSwap, (swapFee, order, signature)),
                gasLimit: 12_000
            });
            interactions[0][1] = ICowSettlement.Interaction({
                target: address(hooksTrampoline),
                value: 0,
                callData: abi.encodeCall(hooksTrampoline.execute, (hooks))
            });
        }

        interactions[1][0] = ICowSettlement.Interaction({
            target: address(token0),
            value: 0,
            callData: abi.encodeCall(token0.approve, (address(routerMock), amountIn))
        });
        interactions[1][1] = ICowSettlement.Interaction({
            target: address(routerMock),
            value: 0,
            callData: abi.encodeCall(routerMock.swapAssets, (address(token0), address(token1), amountIn, amountOut))
        });

        bytes memory settlement;
        {
            address[] memory tokens = new address[](2);
            tokens[0] = address(token0);
            tokens[1] = address(token1);

            uint256[] memory clearingPrices = new uint256[](2);
            clearingPrices[0] = order.buyAmount;
            clearingPrices[1] = order.sellAmount;

            ICowSettlement.Trade[] memory trades = new ICowSettlement.Trade[](1);
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
                abi.encodePacked(address(cowSwapper), bytes(""))
            );

            settlement = abi.encodeCall(ICowSettlement.settle, (tokens, clearingPrices, trades, interactions));
        }

        deal(address(token0), users.accountOwner, amountIn, true);
        deal(address(token1), address(routerMock), amountOut, true);
        {
            address[] memory assets_ = new address[](1);
            uint256[] memory assetIds_ = new uint256[](1);
            uint256[] memory assetAmounts_ = new uint256[](1);

            assets_[0] = address(token0);
            assetAmounts_[0] = amountIn;

            // And : Deposit position in Account
            vm.startPrank(users.accountOwner);
            token0.approve(address(account), amountIn);
            account.deposit(assets_, assetIds_, assetAmounts_);
            vm.stopPrank();
        }

        vm.prank(solver);
        flashLoanRouter.flashLoanAndSettle(loans, settlement);
    }

    function getSignature(address account_, uint256 swapFee, GPv2Order.Data memory order, uint256 privateKey)
        public
        view
        returns (bytes memory sig)
    {
        bytes32 messageHash = keccak256(abi.encode(account_, swapFee, order.hash(cowSwapper.DOMAIN_SEPARATOR())));
        sig = getSignature(messageHash, privateKey);
    }

    function getSignature(bytes32 messageHash, uint256 privateKey) public pure returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, messageHash);
        return bytes.concat(r, s, bytes1(v));
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
}
