// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShareFactory} from "../src/RevenueShareFactory.sol";

/// @notice Deploys RWA Revenue Rails (RevenueShareFactory) to Robinhood Chain.
///
///   forge script script/DeployRevenue.s.sol --rpc-url robinhood \
///     --account servo-deployer --broadcast
///
/// Settlement currency defaults to USDG on Robinhood Chain; override with USDG env.
contract DeployRevenue is Script {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    function run() external {
        address asset = vm.envOr("USDG", USDG);

        vm.startBroadcast();
        RevenueShareFactory factory = new RevenueShareFactory(IERC20(asset));
        vm.stopBroadcast();

        console.log("RevenueShareFactory:", address(factory));
        console.log("Settlement asset:   ", asset);
    }
}
