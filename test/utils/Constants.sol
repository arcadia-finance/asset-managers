/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.22;

library Constants {
    // Users
    address payable constant OWNER = payable(0xb4d72B1c91e640e4ED7d7397F3244De4D8ACc50B);
    address payable constant GUARDIAN = payable(0xEdD41f9740b06eCBfe1CE9194Ce2715C28263187);
    address payable constant RISK_MANAGER = payable(0xD5FA6C6e284007743d4263255385eDA78dDa268c);

    // Deployed contracts
    address payable constant ACCOUNTV1 = payable(0xbea2B6d45ACaF62385877D835970a0788719cAe1);
    address payable constant CHAINLINK_OM = payable(0x6a5485E3ce6913890ae5e8bDc08a868D432eEB31);
    address payable constant ERC20_AM = payable(0xfBecEaFC96ed6fc800753d3eE6782b6F9a60Eed7);
    address payable constant FACTORY = payable(0xDa14Fdd72345c4d2511357214c5B89A919768e59);
    address payable constant REGISTRY = payable(0xd0690557600eb8Be8391D1d97346e2aab5300d5f);
    address payable constant STARGATE_AM = payable(0x20f7903290bF98716B62Dc1c9DA634291b8cfeD4);
    address payable constant STAKED_STARGATE_AM = payable(0xae909e19fd13C01c28d5Ee439D403920CF7f9Eea);
    address payable constant UNIV3_AM = payable(0x21bd524cC54CA78A7c48254d4676184f781667dC);

    // Upgrade root
    bytes32 internal constant UPGRADE_ROOT_1_To_1 = 0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f;
}
