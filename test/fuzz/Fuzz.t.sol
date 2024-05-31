/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

import { Base_Test } from "../Base.t.sol";

import { AccountV1 } from "../../lib/accounts-v2/src/accounts/AccountV1.sol";
import { ChainlinkOMExtension } from "../../lib/accounts-v2/test/utils/extensions/ChainlinkOMExtension.sol";
import { Constants } from "../utils/Constants.sol";
import { ERC20 } from "../../lib/accounts-v2/lib/solmate/src/tokens/ERC20.sol";
import { ERC20PrimaryAMExtension } from "../../lib/accounts-v2/test/utils/extensions/ERC20PrimaryAMExtension.sol";
import { Factory } from "../../lib/accounts-v2/src/Factory.sol";
import { INonfungiblePositionManagerExtension } from
    "../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/INonfungiblePositionManagerExtension.sol";
import { IUniswapV3PoolExtension } from
    "../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/extensions/interfaces/IUniswapV3PoolExtension.sol";
import { RegistryExtension } from "../../lib/accounts-v2/test/utils/extensions/RegistryExtension.sol";
import { QuoterV2Fixture } from "../utils/fixtures/quoter-v2/QuoterV2Fixture.f.sol";
import { SequencerUptimeOracle } from "../../lib/accounts-v2/test/utils/mocks/oracles/SequencerUptimeOracle.sol";
import { SwapRouter02Fixture } from "../../lib/accounts-v2/test/utils/fixtures/swap-router-02/SwapRouter02Fixture.f.sol";
import { UniswapV3Fixture } from "../../lib/accounts-v2/test/utils/fixtures/uniswap-v3/UniswapV3Fixture.f.sol";
import { UniswapV3AMExtension } from "../../lib/accounts-v2/test/utils/extensions/UniswapV3AMExtension.sol";
import { Utils } from "../../lib/accounts-v2/test/utils/Utils.sol";

/**
 * @notice Common logic needed by all fuzz tests.
 * @dev Each function must be fuzz tested over its full space of possible state configurations
 * (both the state variables of the contract being tested
 * as the state variables of any external contract with which the function interacts).
 * @dev in practice each input parameter and state variable (as explained above) must be tested over its full range
 * (eg. a uint256 from 0 to type(uint256).max), unless the parameter/variable is bound by an invariant.
 * If this case, said invariant must be explicitly tested in the invariant tests.
 */
abstract contract Fuzz_Test is Base_Test, UniswapV3Fixture, SwapRouter02Fixture, QuoterV2Fixture {
    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    SequencerUptimeOracle internal sequencerUptimeOracle;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override(Base_Test, UniswapV3Fixture) {
        Base_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function deployArcadiaAccounts() public {
        // Warp to have a timestamp of at least two days old.
        vm.warp(2 days);

        // Create Users.
        users.accountOwner = createUser("accountOwner");

        // Deploy Arcadia  Accounts Contracts.
        vm.startPrank(users.owner);
        factory = new Factory();
        sequencerUptimeOracle = new SequencerUptimeOracle();
        registry = new RegistryExtension(address(factory), address(sequencerUptimeOracle));

        AccountV1 accountV1Logic = new AccountV1(address(factory));
        factory.setNewAccountInfo(address(registry), address(accountV1Logic), Constants.UPGRADE_ROOT_1_To_1, "");

        chainlinkOM = new ChainlinkOMExtension(address(registry));
        registry.addOracleModule(address(chainlinkOM));

        erc20AM = new ERC20PrimaryAMExtension(address(registry));
        registry.addAssetModule(address(erc20AM));

        factory.changeGuardian(users.guardian);
        registry.changeGuardian(users.guardian);
        vm.stopPrank();

        // Create Account.
        vm.prank(users.accountOwner);
        account = AccountV1(factory.createAccount(0, 0, address(0)));
    }

    function deploySwapRouter02() public {
        SwapRouter02Fixture.deploySwapRouter02(
            address(0), address(uniswapV3Factory), address(nonfungiblePositionManager), address(weth9)
        );
    }

    function deployQuoterV2() public {
        QuoterV2Fixture.deployQuoterV2(address(uniswapV3Factory), address(weth9));
    }

    function deployUniswapV3() public {
        UniswapV3Fixture.setUp();
    }

    function deployUniswapV3AM() internal {
        // Deploy Add the Asset Module to the Registry.
        vm.startPrank(users.owner);
        uniV3AM = new UniswapV3AMExtension(address(registry), address(nonfungiblePositionManager));
        registry.addAssetModule(address(uniV3AM));
        uniV3AM.setProtocol();
        vm.stopPrank();

        // Get the bytecode of the UniswapV3PoolExtension.
        bytes memory args = abi.encode();
        bytes memory bytecode = abi.encodePacked(vm.getCode("UniswapV3PoolExtension.sol"), args);
        bytes32 poolExtensionInitCodeHash = keccak256(bytecode);
        bytes32 POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

        // Overwrite code hash of the UniswapV3AMExtension.
        bytecode = address(uniV3AM).code;
        bytecode = Utils.veryBadBytesReplacer(bytecode, POOL_INIT_CODE_HASH, poolExtensionInitCodeHash);
        vm.etch(address(uniV3AM), bytecode);
    }

    function createPool(address token0, address token1, uint24 fee, uint160 sqrtPriceX96, uint16 observationCardinality)
        public
        returns (IUniswapV3PoolExtension uniV3Pool_)
    {
        address poolAddress =
            nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, fee, sqrtPriceX96);
        uniV3Pool_ = IUniswapV3PoolExtension(poolAddress);
        uniV3Pool_.increaseObservationCardinalityNext(observationCardinality);
    }

    function addLiquidity(
        IUniswapV3PoolExtension pool_,
        uint256 amount0,
        uint256 amount1,
        address liquidityProvider_,
        int24 tickLower,
        int24 tickUpper
    ) public returns (uint256 tokenId, uint256 amount0_, uint256 amount1_) {
        address token0 = pool_.token0();
        address token1 = pool_.token1();
        uint24 fee = pool_.fee();

        deal(token0, liquidityProvider_, amount0, true);
        deal(token1, liquidityProvider_, amount1, true);
        vm.startPrank(liquidityProvider_);
        ERC20(token0).approve(address(nonfungiblePositionManager), type(uint256).max);
        ERC20(token1).approve(address(nonfungiblePositionManager), type(uint256).max);
        (tokenId,, amount0_, amount1_) = nonfungiblePositionManager.mint(
            INonfungiblePositionManagerExtension.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: liquidityProvider_,
                deadline: type(uint256).max
            })
        );
        vm.stopPrank();
    }
}
