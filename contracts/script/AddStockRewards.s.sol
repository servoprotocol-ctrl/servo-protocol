// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {UniswapV4SwapAdapter} from "../src/UniswapV4SwapAdapter.sol";
import {PoolKey} from "../src/interfaces/IPoolManagerMinimal.sol";

/// @notice Adds more claimable stocks to the live StockRewards. Each token's v4 pool
///         was validated against its Chainlink feed (all within 3% of oracle price,
///         2026-07-17). Pins the adapter pool and allow-lists the token. NVDA stays the
///         default. Run from the gov/owner (deployer).
contract AddStockRewards is Script {
    StockRewards constant REWARDS = StockRewards(0x56E80cB3eE4ccF34bFC1A9F0d23EC0FC1C8a40c7);
    UniswapV4SwapAdapter constant ADAPTER = UniswapV4SwapAdapter(0x4F6A5Ac90a6D1E4a27c78c84e948cD13237682bB);
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    struct Stock {
        address token;
        uint24 fee;
        int24 tickSpacing;
    }

    function run() external {
        Stock[7] memory stocks = [
            Stock(0x322F0929c4625eD5bAd873c95208D54E1c003b2d, 3000, 60), // TSLA
            Stock(0x12f190a9F9d7D37a250758b26824B97CE941bF54, 3000, 60), // AMZN
            Stock(0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3, 3000, 60), // GOOGL
            Stock(0x117cc2133c37B721F49dE2A7a74833232B3B4C0C, 3000, 60), // SPY
            Stock(0x894E1EC2D74FFE5AEF8Dc8A9e84686acCB964F2A, 20000, 400), // PLTR
            Stock(0xe93237C50D904957Cf27E7B1133b510C669c2e74, 20000, 400), // MSFT
            Stock(0x86923f96303D656E4aa86D9d42D1e57ad2023fdC, 10000, 200) // AMD
        ];

        vm.startBroadcast();
        for (uint256 i = 0; i < stocks.length; i++) {
            address t = stocks[i].token;
            (address c0, address c1) = USDG < t ? (USDG, t) : (t, USDG);
            ADAPTER.setPool(t, PoolKey({currency0: c0, currency1: c1, fee: stocks[i].fee, tickSpacing: stocks[i].tickSpacing, hooks: address(0)}));
            REWARDS.setAllowedStock(t, true);
        }
        vm.stopBroadcast();

        console.log("Added 7 stocks: TSLA AMZN GOOGL SPY PLTR MSFT AMD");
    }
}
