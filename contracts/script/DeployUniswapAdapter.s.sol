// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {UniswapV3SwapAdapter, IV3SwapRouter} from "../src/UniswapV3SwapAdapter.sol";

/// @notice Deploys the Uniswap v3 swap adapter for StockRewards.
///
/// Required env:
///   UNIV3_ROUTER  - the VERIFIED Uniswap v3 SwapRouter02 on the target chain.
///                   Confirm on robinhoodchain.blockscout.com before mainnet; the
///                   chain's Universal Router is a modified fork with look-alike decoys.
/// Optional env:
///   SERVO_GOV     - owner (defaults to deployer).
///
/// After deploy, per stock token, set the v3 path (owner):
///   adapter.setPath(STOCK, abi.encodePacked(USDG, uint24 fee, STOCK))            // direct pool
///   adapter.setPath(STOCK, abi.encodePacked(USDG, feeA, WETH, feeB, STOCK))      // multi-hop
/// Then wire it into rewards (owner):
///   stockRewards.setSwapAdapter(adapter)
///   stockRewards.setAllowedStock(STOCK, true) [/ setDefaultStock(STOCK)]
///
/// Reference (Robinhood Chain mainnet): USDG 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168,
/// NVDA Chainlink feed 0x379EC4f7C378F34a1B47E4F3cbeBCbAC3E8E9F15 (price reference, not the token).
contract DeployUniswapAdapter is Script {
    function run() external {
        address router = vm.envAddress("UNIV3_ROUTER");
        address owner = vm.envOr("SERVO_GOV", msg.sender);

        vm.startBroadcast();
        UniswapV3SwapAdapter adapter = new UniswapV3SwapAdapter(IV3SwapRouter(router), owner);
        vm.stopBroadcast();

        console.log("UniswapV3SwapAdapter:", address(adapter));
        console.log("router:", router);
        console.log("owner:", owner);
    }
}
