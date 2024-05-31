/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Test } from "../lib/accounts-v2/lib/forge-std/src/Test.sol";

import { AccountV1 } from "../lib/accounts-v2/src/accounts/AccountV1.sol";
import { ArcadiaOracle } from "../lib/accounts-v2/test/utils/mocks/oracles/ArcadiaOracle.sol";
import { BitPackingLib } from "../lib/accounts-v2/src/libraries/BitPackingLib.sol";
import { ChainlinkOMExtension } from "../lib/accounts-v2/test/utils/extensions/ChainlinkOMExtension.sol";
import { Constants } from "./utils/Constants.sol";
import { ERC20Mock } from "../lib/accounts-v2/test/utils/mocks/tokens/ERC20Mock.sol";
import { ERC20PrimaryAMExtension } from "../lib/accounts-v2/test/utils/extensions/ERC20PrimaryAMExtension.sol";
import { Factory } from "../lib/accounts-v2/src/Factory.sol";
import { RegistryExtension } from "../lib/accounts-v2/test/utils/extensions/RegistryExtension.sol";
import { UniswapV3AMExtension } from "../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { Users } from "./utils/Types.sol";

/// @notice Base test contract with common logic needed by all tests in Liquidation repo.
abstract contract Base_Test is Test {
    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    // baseToQuoteAsset arrays
    bool[] internal BA_TO_QA_SINGLE = new bool[](1);
    bool[] internal BA_TO_QA_DOUBLE = new bool[](2);

    /*//////////////////////////////////////////////////////////////////////////
                                  VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    AccountV1 internal account;
    ChainlinkOMExtension internal chainlinkOM;
    ERC20PrimaryAMExtension internal erc20AM;
    Factory internal factory;
    RegistryExtension internal registry;
    UniswapV3AMExtension internal uniV3AM;
    Users internal users;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////////////////
                                SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    constructor() {
        BA_TO_QA_SINGLE[0] = true;
        BA_TO_QA_DOUBLE[0] = true;
        BA_TO_QA_DOUBLE[1] = true;
    }

    function setUp() public virtual {
        // Create users.
        users.owner = Constants.OWNER;
        users.deployer = createUser("deployer");
        users.liquidityProvider = createUser("liquidityProvider");
        users.oracleOwner = createUser("oracleOwner");
        users.tokenCreator = createUser("tokenCreator");
        users.transmitter = createUser("transmitter");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/
    function createUser(string memory name) internal returns (address payable) {
        address payable user = payable(makeAddr(name));
        vm.deal({ account: user, newBalance: 100 ether });
        return user;
    }

    function initMockedOracle(string memory description, int256 price) public returns (address) {
        vm.startPrank(users.oracleOwner);
        ArcadiaOracle oracle = new ArcadiaOracle(18, description, address(0));
        oracle.setOffchainTransmitter(users.transmitter);
        vm.stopPrank();

        vm.prank(users.transmitter);
        oracle.transmit(price);

        return address(oracle);
    }

    function initAndAddAsset(string memory name, string memory symbol, uint8 decimals, int256 price)
        public
        returns (address)
    {
        vm.prank(users.tokenCreator);
        ERC20Mock asset = new ERC20Mock(name, symbol, decimals);

        AddAsset(asset, price);

        return address(asset);
    }

    function AddAsset(ERC20Mock asset, int256 price) public {
        address oracle = initMockedOracle(string.concat(asset.name(), " / USD"), price);

        vm.startPrank(users.owner);
        chainlinkOM.addOracle(oracle, bytes16(bytes(asset.name())), "USD", 2 days);

        uint80[] memory oracles = new uint80[](1);
        oracles[0] = uint80(chainlinkOM.oracleToOracleId(oracle));
        erc20AM.addAsset(address(asset), BitPackingLib.pack(BA_TO_QA_SINGLE, oracles));
        vm.stopPrank();
    }
}
