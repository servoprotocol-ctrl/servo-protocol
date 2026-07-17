// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV4SwapAdapter} from "../src/UniswapV4SwapAdapter.sol";
import {IPoolManagerMinimal, PoolKey} from "../src/interfaces/IPoolManagerMinimal.sol";

/// @notice Deploys the Uniswap v4 swap adapter and pins the USDG/NVDA pool.
///
/// Verified on Robinhood Chain mainnet (2026-07-17):
///   - PoolManager (v4 singleton, from Uniswap's sdk-core ROBINHOOD_ADDRESSES)
///   - NVDA = the BeaconProxy stock token (13k+ holders), NOT the look-alike clones
///   - Live pool: USDG/NVDA fee 3000 (0.30%), tickSpacing 60, hooks 0x0 — quoted
///     1,000 USDG -> ~4.855 NVDA (~0.05% impact) via the v4 quoter.
///
/// After deploy, wire into rewards (owner):
///   stockRewards.setSwapAdapter(adapter)
///   stockRewards.setAllowedStock(NVDA, true); stockRewards.setDefaultStock(NVDA)
contract DeployV4Adapter is Script {
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    function run() external {
        address owner = vm.envOr("SERVO_GOV", msg.sender);

        vm.startBroadcast();
        UniswapV4SwapAdapter adapter = new UniswapV4SwapAdapter(IPoolManagerMinimal(POOL_MANAGER), owner);

        (address c0, address c1) = USDG < NVDA ? (USDG, NVDA) : (NVDA, USDG);
        adapter.setPool(NVDA, PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)}));
        vm.stopBroadcast();

        console.log("UniswapV4SwapAdapter:", address(adapter));
        console.log("poolManager:", POOL_MANAGER);
        console.log("NVDA pool pinned: USDG/NVDA fee=3000 ts=60 hooks=0x0");
        console.log("owner:", owner);
    }
}
