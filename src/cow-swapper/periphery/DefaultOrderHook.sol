/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { GPv2Order, IERC20 } from "../../../lib/cowprotocol/src/contracts/libraries/GPv2Order.sol";
import { ICowSwapper } from "../interfaces/ICowSwapper.sol";
import { IGPv2Settlement } from "../interfaces/IGPv2Settlement.sol";
import { OrderHook } from "./OrderHook.sol";
import { LibString } from "../../../lib/accounts-v2/lib/solady/src/utils/LibString.sol";

/**
 * @title Order Hook.
 * @author Pragma Labs
 */
contract DefaultOrderHook is OrderHook {
    using GPv2Order for GPv2Order.Data;
    using LibString for string;
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The domain separator used for signing orders.
    bytes32 public immutable DOMAIN_SEPARATOR;

    // The contract address of the CoW Swapper.
    address public immutable COW_SWAPPER;
    /// forge-lint: disable-next-line(mixed-case-variable)
    string internal COW_SWAPPER_HEX_STRING;

    // Offsets to decode the initiatorData.
    uint256 internal constant OFFSET_96_BITS = 96;
    uint256 internal constant OFFSET_2_BYTES = 2;
    uint256 internal constant OFFSET_6_BYTES = 6;
    uint256 internal constant OFFSET_14_BYTES = 14;

    /* //////////////////////////////////////////////////////////////
                               STORAGE
    ////////////////////////////////////////////////////////////// */

    // A mapping from an Arcadia Account to a struct with Account-specific information.
    mapping(address cowSwapper => mapping(address account => AccountInfo)) public accountInfo;

    // A struct containing Account-specific information.
    struct AccountInfo {
        // A bytes array containing custom information.
        bytes customInfo;
    }

    /* //////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param cowSwapper The contract address of the CoW Swapper.
     */
    constructor(address cowSwapper) {
        COW_SWAPPER = cowSwapper;
        COW_SWAPPER_HEX_STRING = LibString.toHexString(cowSwapper);

        DOMAIN_SEPARATOR = IGPv2Settlement(ICowSwapper(cowSwapper).settlementContract()).domainSeparator();
    }

    /* ///////////////////////////////////////////////////////////////
                            ACCOUNT LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Function called by the CoW Swapper to set the Account specific information.
     * @param account The contract address of the Arcadia Account to set the order info for.
     * @param hookData Encoded data containing hook specific parameters.
     */
    function setHook(address account, bytes calldata hookData) external override {
        (bytes memory customInfo) = abi.decode(hookData, (bytes));

        accountInfo[msg.sender][account] = AccountInfo({ customInfo: customInfo });
    }

    /* ///////////////////////////////////////////////////////////////
                            PRE SWAP HOOK
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Hook called to validate and calculate the initiator parameters.
     * @param account The contract address of the Arcadia Account.
     * @param tokenIn The contract address of the token to swap from.
     * @param amountIn The amount of tokenIn to swap.
     * @param initiatorData The packed encoded remaining initiator parameters.
     * encodePacked(address tokenOut, uint112 amountOut, uint32 validTo, uint64 swapFee)
     * @return swapFee The fee charged on the amountOut by the initiator, with 18 decimals precision.
     * @return tokenOut The contract address of the token to swap to.
     * @return orderHash The order hash.
     */
    function getInitiatorParams(address account, address tokenIn, uint256 amountIn, bytes calldata initiatorData)
        external
        view
        override
        returns (uint64 swapFee, address tokenOut, bytes32 orderHash)
    {
        uint256 amountOut;
        uint32 validTo;
        (tokenOut, amountOut, validTo, swapFee) = _decodeInitiatorData(initiatorData);

        GPv2Order.Data memory order = GPv2Order.Data({
            sellToken: IERC20(tokenIn),
            buyToken: IERC20(tokenOut),
            receiver: COW_SWAPPER,
            sellAmount: amountIn,
            buyAmount: amountOut,
            validTo: validTo,
            appData: getAppDataHash(
                account, tokenIn, amountIn, abi.encodeCall(ICowSwapper.beforeSwap, (initiatorData))
            ),
            feeAmount: 0,
            kind: GPv2Order.KIND_SELL,
            partiallyFillable: false,
            sellTokenBalance: GPv2Order.BALANCE_ERC20,
            buyTokenBalance: GPv2Order.BALANCE_ERC20
        });

        orderHash = order.hash(DOMAIN_SEPARATOR);
    }

    /**
     * @notice Decodes the initiatorData.
     * @param initiatorData The packed encoded remaining initiator parameters.
     * encodePacked(address tokenOut, uint112 amountOut, uint32 validTo, uint64 swapFee)
     * @return tokenOut The contract address of the token to swap to.
     * @return amountOut The amount of tokenOut to swap to.
     * @return validTo The time at which the order will stop being valid.
     * @return swapFee The fee charged on the amountOut by the initiator, with 18 decimals precision.
     * @dev since the beforeSwap calldata has to be converted to hexString, the initiatorData is packed as tightly as possible.
     */
    function _decodeInitiatorData(bytes calldata initiatorData)
        internal
        pure
        returns (address tokenOut, uint112 amountOut, uint32 validTo, uint64 swapFee)
    {
        assembly {
            // Load first 256 bits of initiatorData and shift right by 96 bits to extract tokenOut.
            tokenOut := shr(OFFSET_96_BITS, calldataload(initiatorData.offset))
            // Load bits 16 to 272 (offset of 2 bytes) of initiatorData, dirty upper bits are zeroed out by casting to uint112.
            amountOut := calldataload(add(initiatorData.offset, OFFSET_2_BYTES))
            // Load bits 48 to 304 (offset of 6 bytes) of initiatorData, dirty upper bits are zeroed out by casting to uint32.
            validTo := calldataload(add(initiatorData.offset, OFFSET_6_BYTES))
            // Load bits 112 to 368 (offset of 14 bytes) of initiatorData, dirty upper bits are zeroed out by casting to uint64.
            swapFee := calldataload(add(initiatorData.offset, OFFSET_14_BYTES))
        }
    }

    /* ///////////////////////////////////////////////////////////////
                            APP DATA LOGIC
    /////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns the AppData Hash of the swap.
     * @param account The contract address of the Arcadia Account.
     * @param tokenIn The contract address of the token to swap from.
     * @param amountIn The amount of tokenIn to swap.
     * @param beforeSwapCallData The calldata of the beforeSwap() hook.
     * @return appDataHash The AppData Hash.
     * @dev The AppData JSON string must match the metadata passed when submitting the swap.
     */
    function getAppDataHash(address account, address tokenIn, uint256 amountIn, bytes memory beforeSwapCallData)
        public
        view
        returns (bytes32 appDataHash)
    {
        appDataHash = keccak256(bytes(getAppData(account, tokenIn, amountIn, beforeSwapCallData)));
    }

    /**
     * @notice Returns the AppData of the swap.
     * @param account The contract address of the Arcadia Account.
     * @param tokenIn The contract address of the token to swap from.
     * @param amountIn The amount of tokenIn to swap.
     * @param beforeSwapCallData The calldata of the beforeSwap() hook.
     * @return appData The AppData JSON string.
     * @dev The AppData JSON string must match the metadata passed when submitting the swap.
     */
    function getAppData(address account, address tokenIn, uint256 amountIn, bytes memory beforeSwapCallData)
        public
        view
        returns (string memory appData)
    {
        appData = string.concat(
            '{"appCode":"Arcadia 0.1.0","metadata":{"flashloan":{"amount":"',
            LibString.toString(amountIn),
            '","liquidityProvider":"',
            LibString.toHexString(account),
            '","protocolAdapter":"',
            COW_SWAPPER_HEX_STRING,
            '","receiver":"',
            COW_SWAPPER_HEX_STRING,
            '","token":"',
            LibString.toHexString(tokenIn),
            '"},"hooks":{"pre":[{"callData":"',
            LibString.toHexString(beforeSwapCallData),
            '","gasLimit":"80000","target":"',
            COW_SWAPPER_HEX_STRING,
            '"}],"version":"0.2.0"}},"version":"1.11.0"}'
        );
    }
}
