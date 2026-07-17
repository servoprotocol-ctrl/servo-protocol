// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {MachineAccount} from "../src/MachineAccount.sol";
import {MachineAccountFactory} from "../src/MachineAccountFactory.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {UniswapV4SwapAdapter} from "../src/UniswapV4SwapAdapter.sol";
import {IPoolManagerMinimal, PoolKey} from "../src/interfaces/IPoolManagerMinimal.sol";

/// @notice Go-live for marketplace stock rewards on Robinhood Chain, in one broadcast:
///
///   1. Deploy StockRewards (USDG-funded dividend pool)
///   2. Deploy UniswapV4SwapAdapter and pin the live USDG/NVDA pool
///   3. Deploy ServiceRegistry v2 (fee-split hook) + a MachineAccountFactory bound to it
///   4. Cut over: v2 becomes a commerce recorder, v1's charging listing is deactivated
///      and re-listed on v2 (same price, same payTo: the sCHG revenue share)
///   5. Wire rewards at 50/50: half the 1pct protocol fee becomes buyer stock dividends
///   6. Create the delivery bot's new MachineAccount on v2 (existing bound key carries
///      over via the registry) with the same 5 USDG/day cap
contract DeployRewardsStack is Script {
    // Live Servo contracts (Robinhood Chain 4663)
    MachineRegistry constant REGISTRY = MachineRegistry(0x7896Dba19A72278d66C9f0640262C511D24CB871);
    ServiceRegistry constant SERVICES_V1 = ServiceRegistry(0x24f2f3536F65CA2AE36136E3B217a390251a1a90);
    address constant SCHG = 0x664b19AC98fEb5051d4aE659eBb4D8B6e326CD0e; // charger revenue share (payTo)

    // Chain infrastructure (verified 2026-07-17)
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    uint16 constant REWARD_SHARE_BPS = 5000; // half the protocol fee -> buyer dividends
    uint96 constant CHARGE_PRICE = 50_000; // 0.05 USDG, as on v1
    bytes32 constant CATEGORY_CHARGING = keccak256("CHARGING");

    function run() external {
        address gov = msg.sender; // deployer is gov/treasury (Option A)

        vm.startBroadcast();

        // 1. rewards pool
        StockRewards rewards = new StockRewards(IERC20(USDG), gov);

        // 2. swap adapter pinned to the live USDG/NVDA 0.30% pool (hooks 0x0)
        UniswapV4SwapAdapter adapter = new UniswapV4SwapAdapter(IPoolManagerMinimal(POOL_MANAGER), gov);
        (address c0, address c1) = USDG < NVDA ? (USDG, NVDA) : (NVDA, USDG);
        adapter.setPool(NVDA, PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)}));

        // 3. marketplace v2 + account factory bound to it
        ServiceRegistry servicesV2 = new ServiceRegistry(REGISTRY, gov, gov);
        MachineAccountFactory factoryV2 = new MachineAccountFactory(REGISTRY, servicesV2);

        // 4. cutover: v2 records commerce, v1 stops; charging re-listed on v2
        REGISTRY.setRecorder(address(servicesV2), true);
        REGISTRY.setRecorder(address(SERVICES_V1), false);
        SERVICES_V1.updateService(1, SCHG, CHARGE_PRICE, false, "https://servoprotocol.xyz/svc/1");
        uint256 svcId = servicesV2.registerService(
            1, SCHG, USDG, CHARGE_PRICE, CATEGORY_CHARGING, false, "https://servoprotocol.xyz/svc/1"
        );

        // 5. wire stock rewards, 50/50 split
        rewards.setRecorder(address(servicesV2), true);
        rewards.setSwapAdapter(address(adapter));
        rewards.setAllowedStock(NVDA, true);
        rewards.setDefaultStock(NVDA);
        servicesV2.setStockRewards(address(rewards), REWARD_SHARE_BPS);

        // 6. bot's new account on v2 (bound machine key carries over via the registry)
        address botAccount = factoryV2.createAccount(2);
        MachineAccount(payable(botAccount)).setDailyCap(USDG, 5e6); // 5 USDG/day, as before

        vm.stopBroadcast();

        console.log("StockRewards:        ", address(rewards));
        console.log("UniswapV4SwapAdapter:", address(adapter));
        console.log("ServiceRegistry v2:  ", address(servicesV2));
        console.log("AccountFactory v2:   ", address(factoryV2));
        console.log("Charging service id: ", svcId);
        console.log("Bot account v2:      ", botAccount);
    }
}
