// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {Script, console} from "forge-std/Script.sol";
import {ServoOracle} from "../src/ServoOracle.sol";
contract DeployOracle is Script {
    address constant USDG_USD_FEED = 0x8bEeE3503F6860D5dac4cE26b5eEe92982951c2e; // Chainlink USDG/USD on Robinhood Chain
    function run() external {
        vm.startBroadcast();
        ServoOracle o = new ServoOracle(USDG_USD_FEED);
        vm.stopBroadcast();
        console.log("ServoOracle:", address(o));
    }
}
