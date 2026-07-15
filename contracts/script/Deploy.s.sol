// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {MachineAccountFactory} from "../src/MachineAccountFactory.sol";

/// @notice Deploys the Servo core to Robinhood Chain / Robinhood Chain testnet.
///
///   forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast \
///     --account <keystore> [--verify]
///
/// Env:
///   SERVO_GOV       protocol owner (defaults to deployer)
///   SERVO_TREASURY  protocol fee destination (defaults to deployer)
contract Deploy is Script {
    function run() external {
        address deployer = msg.sender;
        address gov = vm.envOr("SERVO_GOV", deployer);
        address treasury = vm.envOr("SERVO_TREASURY", deployer);

        vm.startBroadcast();
        // Own the registry during setup so we can authorize the ServiceRegistry
        // as the sole commerce recorder, then hand governance to `gov`.
        MachineRegistry registry = new MachineRegistry(deployer);
        ServiceRegistry services = new ServiceRegistry(registry, gov, treasury);
        MachineAccountFactory factory = new MachineAccountFactory(registry, services);

        registry.setRecorder(address(services), true);
        if (gov != deployer) registry.transferOwnership(gov);
        vm.stopBroadcast();

        console.log("MachineRegistry:      ", address(registry));
        console.log("ServiceRegistry:      ", address(services));
        console.log("MachineAccountFactory:", address(factory));
        console.log("Governance:           ", gov);
        console.log("Treasury:             ", treasury);
    }
}
