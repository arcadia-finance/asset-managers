/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.22;

struct Users {
    address payable accountOwner;
    address payable deployer;
    address payable guardian;
    address payable liquidityProvider;
    address payable oracleOwner;
    address payable owner;
    address payable riskManager;
    address payable tokenCreator;
    address payable transmitter;
}
