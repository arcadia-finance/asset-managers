/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { AccountV3 } from "../lib/accounts-v2/src/accounts/AccountV3.sol";
import { CowSwapper } from "../src/cow-swapper/CowSwapper.sol";
import { DefaultOrderHook } from "../src/cow-swapper/periphery/DefaultOrderHook.sol";
import { ICowSwapper } from "../src/cow-swapper/interfaces/ICowSwapper.sol";
import { Test } from "../lib/accounts-v2/lib/forge-std/src/Test.sol";

contract Deploy is Test {
    address internal constant DEPLOYER = 0x29E923A6DE8761FdBE2a57618a978F1C3cEE6bdF;
    address internal constant FACTORY = 0xDa14Fdd72345c4d2511357214c5B89A919768e59;
    address internal constant FLASH_LOAN_ROUTER = 0x9da8B48441583a2b93e2eF8213aAD0EC0b392C69;
    address internal constant HOOKS_TRAMPOLINE = 0x60Bf78233f48eC42eE3F101b9a05eC7878728006;

    function run() external {
        vm.createSelectFork(vm.envString("RPC_URL_BASE"));
        assertEq(8453, block.chainid);

        uint256 sender = vm.envUint("PRIVATE_KEY_MANAGER");
        require(vm.addr(sender) == DEPLOYER, "Wrong Deployer.");

        vm.startBroadcast(sender);
        CowSwapper cowSwapper = new CowSwapper(DEPLOYER, FACTORY, FLASH_LOAN_ROUTER, HOOKS_TRAMPOLINE);
        new DefaultOrderHook(address(cowSwapper));
        vm.stopBroadcast();
    }
}

contract Setup is Test {
    address internal constant INITIATOR = 0x29E923A6DE8761FdBE2a57618a978F1C3cEE6bdF;

    address internal constant COW_SWAPPER_V0 = 0x28c44Eb06B37475F32CD08D18ab1720Cc68bFCb3;
    address internal constant ORDER_HOOK_V0 = 0x0C0D0a13aBf795CED4968069b28B38402DE5C8a7;

    address internal constant COW_SWAPPER_V1 = 0xa47559e016ab7f6bE584087b872FC66D6E946149;
    address internal constant ORDER_HOOK_V1 = 0x8fae47263CE64faad5239021c25e244e1276EFe8;

    address internal constant COW_SWAPPER_V2 = 0xFe9a0De13D927cBA480Bf8b64577832BfE532915;
    address internal constant ORDER_HOOK_V2 = 0x63A08DF576e967B3A22Eba7C79c21bEE19550Bb0;

    AccountV3 internal constant ACCOUNT = AccountV3(0xf1029b5623B07b938bd0c597c2Cd9788Bb44a18E);
    address internal constant ACCOUNT_OWNER = 0x12c0b7f365d5229eB33EBab320F34b6609a0A219;

    uint256 internal constant MAX_SWAP_FEE = 0;

    function run() external {
        vm.createSelectFork(vm.envString("RPC_URL_BASE"));
        assertEq(8453, block.chainid);

        uint256 sender = vm.envUint("PRIVATE_KEY_ACCOUNT_OWNER");
        require(vm.addr(sender) == ACCOUNT_OWNER, "Wrong Sender.");

        address[] memory assetManagers = new address[](2);
        bool[] memory statuses = new bool[](2);
        bytes[] memory datas = new bytes[](2);
        assetManagers[0] = COW_SWAPPER_V0;
        assetManagers[1] = COW_SWAPPER_V2;
        statuses[0] = true;
        statuses[1] = true;
        datas[0] = abi.encode(INITIATOR, MAX_SWAP_FEE, ORDER_HOOK_V0, abi.encode(""), "");
        datas[1] = abi.encode(INITIATOR, MAX_SWAP_FEE, ORDER_HOOK_V2, abi.encode(""), "");

        vm.startBroadcast(sender);
        ACCOUNT.setAssetManagers(assetManagers, statuses, datas);
        vm.stopBroadcast();
    }
}

contract Sign is Test {
    address internal constant COW_SWAPPER = 0xFe9a0De13D927cBA480Bf8b64577832BfE532915;
    DefaultOrderHook internal constant ORDER_HOOK = DefaultOrderHook(0x63A08DF576e967B3A22Eba7C79c21bEE19550Bb0);

    AccountV3 internal constant ACCOUNT = AccountV3(0xf1029b5623B07b938bd0c597c2Cd9788Bb44a18E);
    address internal constant ACCOUNT_OWNER = 0x12c0b7f365d5229eB33EBab320F34b6609a0A219;

    address internal constant TOKEN_IN = 0x4200000000000000000000000000000000000006; // WETH
    address internal constant TOKEN_OUT = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC

    uint256 internal constant AMOUNT_IN = 5_000_000_000_000_000; // 0.005 WETH
    uint256 internal constant AMOUNT_OUT = 10_000_000; // 10 USDC

    uint64 internal constant SWAP_FEE = 0;

    function run() external {
        vm.createSelectFork(vm.envString("RPC_URL_BASE"));
        assertEq(8453, block.chainid);

        uint32 validTo = uint32(block.timestamp + 1 hours);

        uint256 accountOwner = vm.envUint("PRIVATE_KEY_ACCOUNT_OWNER");
        require(vm.addr(accountOwner) == ACCOUNT_OWNER, "Wrong Sender.");

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes memory initiatorData = abi.encodePacked(TOKEN_OUT, uint112(AMOUNT_OUT), validTo, SWAP_FEE);
        bytes memory beforeSwapCallData = abi.encodeCall(ICowSwapper.beforeSwap, (initiatorData));

        (,, bytes32 orderHash) = ORDER_HOOK.getInitiatorParams(address(ACCOUNT), TOKEN_IN, AMOUNT_IN, initiatorData);
        emit log_named_bytes32("orderHash", orderHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(accountOwner, orderHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        emit log_named_bytes("signature", signature);

        string memory appData = ORDER_HOOK.getAppData(address(ACCOUNT), TOKEN_IN, AMOUNT_IN, beforeSwapCallData);
        emit log_named_bytes32("appDataHash", keccak256(bytes(appData)));

        emit log_named_string("jsonBody", getJsonBody(signature, escapeJson(appData), validTo));
    }

    function escapeJson(string memory input) internal pure returns (string memory) {
        bytes memory inputBytes = bytes(input);
        uint256 extraChars = 0;

        // Count quotes to know how much extra space we need
        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == '"') {
                extraChars++;
            }
        }

        bytes memory output = new bytes(inputBytes.length + extraChars);
        uint256 j = 0;

        for (uint256 i = 0; i < inputBytes.length; i++) {
            if (inputBytes[i] == '"') {
                output[j++] = "\\";
                output[j++] = '"';
            } else {
                output[j++] = inputBytes[i];
            }
        }

        return string(output);
    }

    function getJsonBody(bytes memory signature, string memory appData, uint32 validTo)
        internal
        pure
        returns (string memory)
    {
        return string.concat(
            '{"sellToken":"',
            vm.toString(TOKEN_IN),
            '","buyToken":"',
            vm.toString(TOKEN_OUT),
            '","receiver":"',
            vm.toString(COW_SWAPPER),
            '","sellAmount":"',
            vm.toString(AMOUNT_IN),
            '","buyAmount":"',
            vm.toString(AMOUNT_OUT),
            '","validTo":',
            vm.toString(validTo),
            ',"feeAmount":"0","kind":"sell","partiallyFillable":false,"sellTokenBalance":"erc20","buyTokenBalance":"erc20","signingScheme":"eip1271","signature":"',
            vm.toString(signature),
            '","from":"',
            vm.toString(COW_SWAPPER),
            '","appData":"',
            appData,
            '"}'
        );
    }
}
