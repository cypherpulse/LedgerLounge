// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {LedgerLounge} from "../src/LedgerLounge.sol";

/**
 * @title DeployLedgerLounge
 * @notice Deployment script for LedgerLounge contract on Celo.
 * @dev Update the cUSD address based on the network (Sepolia or Mainnet).
 */
contract DeployLedgerLounge is Script {
    function run() external returns (LedgerLounge) {
        // Celo Sepolia cUSD address
        address cusd = 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

        vm.startBroadcast();
        LedgerLounge ledgerLounge = new LedgerLounge(cusd);
        vm.stopBroadcast();

        console2.log("LedgerLounge deployed at:", address(ledgerLounge));
        return ledgerLounge;
    }
}