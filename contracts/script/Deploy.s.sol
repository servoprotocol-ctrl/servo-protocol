// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {MachineAccountFactory} from "../src/MachineAccountFactory.sol";

/// @notice Deploys the Servo core to Base / Base Sepolia.
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
        MachineRegistry registry = new MachineRegistry(gov);
        ServiceRegistry services = new ServiceRegistry(registry, gov, treasury);
        MachineAccountFactory factory = new MachineAccountFactory(registry, services);
        vm.stopBroadcast();

        console.log("MachineRegistry:      ", address(registry));
        console.log("ServiceRegistry:      ", address(services));
        console.log("MachineAccountFactory:", address(factory));
        console.log("Governance:           ", gov);
        console.log("Treasury:             ", treasury);
    }
}
