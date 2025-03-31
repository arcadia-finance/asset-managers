/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.22;

import { AerodromeFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/aerodrome/AerodromeFixture.f.sol";
import { CLQuoterFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/CLQuoter.f.sol";
import { CompounderHelper } from "../../../../src/compounders/periphery/CompounderHelper.sol";
import { DefaultUniswapV4AM } from "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/DefaultUniswapV4AM.sol";
import { Fuzz_Test } from "../../Fuzz.t.sol";
import { QuoterV2Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/QuoterV2Fixture.f.sol";
import { SlipstreamAMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/SlipstreamAMExtension.sol";
import { SlipstreamCompounder } from "../../../../src/compounders/slipstream/SlipstreamCompounder.sol";
import { SlipstreamFixture } from "../../../../lib/accounts-v2/test/utils/fixtures/slipstream/Slipstream.f.sol";
import { UniswapV3AMExtension } from "../../../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { UniswapV3Compounder } from "../../../../src/compounders/uniswap-v3/UniswapV3Compounder.sol";
import { UniswapV3Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV4Compounder } from "../../../../src/compounders/uniswap-v4/UniswapV4Compounder.sol";
import { UniswapV4CompounderHelper } from
    "../../../../src/compounders/periphery/uniswap-v4/UniswapV4CompounderHelper.sol";
import { UniswapV4Fixture } from "../../../../lib/accounts-v2/test/utils/fixtures/uniswap-v4/UniswapV4Fixture.f.sol";
import { UniswapV4HooksRegistry } from
    "../../../../lib/accounts-v2/src/asset-modules/UniswapV4/UniswapV4HooksRegistry.sol";
import { Utils } from "../../../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all "CompounderHelper" fuzz tests.
 */
abstract contract CompounderHelper_Fuzz_Test is
    Fuzz_Test,
    UniswapV3Fixture,
    UniswapV4Fixture,
    AerodromeFixture,
    SlipstreamFixture,
    QuoterV2Fixture,
    CLQuoterFixture
{
    /*////////////////////////////////////////////////////////////////
                            CONSTANTS
    /////////////////////////////////////////////////////////////// */
    uint24 internal POOL_FEE = 100;
    int24 internal TICK_SPACING = 1;

    // 5 %
    uint256 MAX_TOLERANCE = 0.05 * 1e18;
    // 4 % price diff for testing
    uint256 TOLERANCE = 0.04 * 1e18;

    // 0,5% to 11% fee on swaps.
    uint256 MIN_INITIATOR_SHARE = 0.005 * 1e18;
    uint256 MAX_INITIATOR_SHARE = 0.11 * 1e18;
    // 10 % initiator fee
    uint256 INITIATOR_SHARE = 0.1 * 1e18;

    /*////////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    address public initiator;

    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    CompounderHelper public compounderHelper;
    DefaultUniswapV4AM internal defaultUniswapV4AM;
    SlipstreamAMExtension internal slipstreamAM;
    SlipstreamCompounder public slipstreamCompounder;
    UniswapV3AMExtension public uniswapV3AM;
    UniswapV3Compounder public uniswapV3Compounder;
    UniswapV4Compounder public uniswapV4Compounder;
    UniswapV4CompounderHelper public uniswapV4CompounderHelper;
    UniswapV4HooksRegistry internal uniswapV4HooksRegistry;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test, UniswapV3Fixture, UniswapV4Fixture, SlipstreamFixture) {
        Fuzz_Test.setUp();

        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Deploy Arcadia Accounts Contracts.
        deployArcadiaAccounts();

        UniswapV3Fixture.setUp();
        QuoterV2Fixture.deployQuoterV2(address(uniswapV3Factory), address(weth9));
        UniswapV4Fixture.setUp();
        AerodromeFixture.deployAerodromePeriphery();
        SlipstreamFixture.setUp();
        SlipstreamFixture.deploySlipstream();
        CLQuoterFixture.deployQuoter(address(cLFactory), address(weth9));

        deployUniswapV3AM();
        deploySlipstreamAM();
        deployUniswapV4AM();

        deployUniswapV3Compounder(MAX_TOLERANCE, MAX_INITIATOR_SHARE);
        deploySlipstreamCompounder(MAX_TOLERANCE, MAX_INITIATOR_SHARE);
        deployUniswapV4Compounder(MAX_TOLERANCE, MAX_INITIATOR_SHARE);

        // And : Compounder is allowed as Asset Manager
        vm.startPrank(users.accountOwner);
        account.setAssetManager(address(uniswapV3Compounder), true);
        account.setAssetManager(address(uniswapV4Compounder), true);
        account.setAssetManager(address(slipstreamCompounder), true);

        // And : Create and set initiator details.
        initiator = createUser("initiator");
        vm.startPrank(initiator);
        slipstreamCompounder.setInitiatorInfo(TOLERANCE, INITIATOR_SHARE);
        uniswapV3Compounder.setInitiatorInfo(TOLERANCE, INITIATOR_SHARE);
        uniswapV4Compounder.setInitiatorInfo(TOLERANCE, INITIATOR_SHARE);

        // And : Set the initiator for the account.
        vm.startPrank(users.accountOwner);
        slipstreamCompounder.setInitiator(address(account), initiator);
        uniswapV3Compounder.setInitiator(address(account), initiator);
        uniswapV4Compounder.setInitiator(address(account), initiator);

        vm.stopPrank();

        // And : Deploy Uniswap V4 Compounder Helper.
        uniswapV4CompounderHelper = new UniswapV4CompounderHelper();
        // Overwrite contract addresses stored as constants in Compounder.
        bytes memory bytecode = address(uniswapV4CompounderHelper).code;
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0),
            abi.encodePacked(address(uniswapV4Compounder)),
            false
        );
        vm.etch(address(uniswapV4CompounderHelper), bytecode);

        // And : Deploy Compounder Helper.
        deployCompounderHelper();
    }

    /*////////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////////*/

    function deployCompounderHelper() public {
        compounderHelper = new CompounderHelper(address(factory), address(uniswapV4CompounderHelper));
        // Overwrite contract addresses stored as constants in Compounder.
        bytes memory bytecode = address(compounderHelper).code;
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0xccc601cFd309894ED7B8F15Cb35057E5A6a18B79),
            abi.encodePacked(address(slipstreamCompounder)),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x254cF9E1E6e233aa1AC962CB9B05b2cfeAaE15b0),
            abi.encodePacked(address(clQuoter)),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x351a4CE4C45029D847F396132953673BcdEAF324),
            abi.encodePacked(address(uniswapV3Compounder)),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a),
            abi.encodePacked(address(quoter)),
            false
        );
        vm.etch(address(compounderHelper), bytecode);
    }

    function deployUniswapV4Compounder(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        uniswapV4Compounder = new UniswapV4Compounder(maxTolerance, maxInitiatorShare);

        // Overwrite contract addresses stored as constants in Compounder.
        bytes memory bytecode = address(uniswapV4Compounder).code;
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x498581fF718922c3f8e6A244956aF099B2652b2b), abi.encodePacked(poolManager), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x7C5f5A4bBd8fD63184577525326123B519429bDc),
            abi.encodePacked(positionManagerV4),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xA3c0c9b65baD0b08107Aa264b0f3dB444b867A71), abi.encodePacked(stateView), false
        );
        vm.etch(address(uniswapV4Compounder), bytecode);
    }

    function deploySlipstreamCompounder(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        slipstreamCompounder = new SlipstreamCompounder(maxTolerance, maxInitiatorShare);

        // Overwrite code hash of the CLPool.
        bytes memory bytecode = address(slipstreamCompounder).code;

        // Overwrite contract addresses stored as constants in slipstreamCompounder.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x827922686190790b37229fd06084350E74485b72),
            abi.encodePacked(slipstreamPositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A), abi.encodePacked(cLFactory), false
        );
        vm.etch(address(slipstreamCompounder), bytecode);
    }

    function deployUniswapV3Compounder(uint256 maxTolerance, uint256 maxInitiatorShare) public {
        vm.prank(users.owner);
        uniswapV3Compounder = new UniswapV3Compounder(maxTolerance, maxInitiatorShare);

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3Pool.
        bytecode = address(uniswapV3Compounder).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);

        // Overwrite contract addresses stored as constants in Compounder.
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xDa14Fdd72345c4d2511357214c5B89A919768e59), abi.encodePacked(factory), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0xd0690557600eb8Be8391D1d97346e2aab5300d5f), abi.encodePacked(registry), false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1),
            abi.encodePacked(nonfungiblePositionManager),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode,
            abi.encodePacked(0x33128a8fC17869897dcE68Ed026d694621f6FDfD),
            abi.encodePacked(uniswapV3Factory),
            false
        );
        bytecode = Utils.veryBadBytesReplacer(
            bytecode, abi.encodePacked(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a), abi.encodePacked(quoter), false
        );
        vm.etch(address(uniswapV3Compounder), bytecode);
    }

    function deployUniswapV3AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniswapV3AM = new UniswapV3AMExtension(address(registry), address(nonfungiblePositionManager));
        registry.addAssetModule(address(uniswapV3AM));
        uniswapV3AM.setProtocol();
        vm.stopPrank();

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3AMExtension.
        bytecode = address(uniswapV3AM).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);
        vm.etch(address(uniswapV3AM), bytecode);
    }

    function deployUniswapV4AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniswapV4HooksRegistry = new UniswapV4HooksRegistry(address(registry), address(positionManagerV4));
        defaultUniswapV4AM = DefaultUniswapV4AM(uniswapV4HooksRegistry.DEFAULT_UNISWAP_V4_AM());

        // Add asset module to Registry.
        registry.addAssetModule(address(uniswapV4HooksRegistry));

        // Set protocol
        uniswapV4HooksRegistry.setProtocol();

        vm.stopPrank();
    }

    function deploySlipstreamAM() public {
        vm.startPrank(users.owner);
        // Add the Asset Module to the Registry.
        slipstreamAM = new SlipstreamAMExtension(address(registry), address(slipstreamPositionManager));

        registry.addAssetModule(address(slipstreamAM));
        slipstreamAM.setProtocol();
        vm.stopPrank();
    }
}
