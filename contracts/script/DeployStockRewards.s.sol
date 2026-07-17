// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Deploys the StockRewards pool for marketplace dividend rewards.
///
/// After deploying, two wiring steps are required (kept manual/governed):
///   1. StockRewards.setRecorder(serviceRegistry, true)
///   2. ServiceRegistry.setStockRewards(stockRewards, rewardShareBps)   // e.g. 5000 = half the fee
///
/// The USDG -> stock swap adapter and the curated stock list are set once the
/// Robinhood Chain DEX venue is confirmed:
///   3. StockRewards.setSwapAdapter(dexAdapter)
///   4. StockRewards.setAllowedStock(stockToken, true) / setDefaultStock(stockToken)
contract DeployStockRewards is Script {
    // USDG (Global Dollar) on Robinhood Chain — the reward currency.
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    function run() external {
        // Governance/owner defaults to the deployer unless overridden.
        address owner = vm.envOr("SERVO_GOV", msg.sender);

        vm.startBroadcast();
        StockRewards rewards = new StockRewards(IERC20(USDG), owner);
        vm.stopBroadcast();

        console.log("StockRewards:", address(rewards));
        console.log("owner:", owner);
        console.log("rewardCurrency (USDG):", USDG);
    }
}
