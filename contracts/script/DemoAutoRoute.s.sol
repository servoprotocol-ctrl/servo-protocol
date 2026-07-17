// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {RevenueShareFactory} from "../src/RevenueShareFactory.sol";
import {RevenueShare} from "../src/RevenueShare.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";

/// @notice Auto-routing demo: tokenize the charging station's income and point its
///         marketplace service revenue directly at the RevenueShare. From now on,
///         every charge the station sells lands in the share and is distributed to
///         its owners on the next sync/claim. The asset earns; the owners get paid.
contract DemoAutoRoute is Script {
    RevenueShareFactory constant FACTORY = RevenueShareFactory(0x4ea7aDfE7501E0a925F89545650A28E7c0797E97);
    ServiceRegistry constant SERVICES = ServiceRegistry(0x24f2f3536F65CA2AE36136E3B217a390251a1a90);
    address constant BACKER = 0x05Bd1b6E853e5cEd23F79167C0023e4294689FA4;

    function run() external {
        address operator = msg.sender;

        vm.startBroadcast();
        RevenueShare share = RevenueShare(
            FACTORY.createRevenueShare("Servo Charger Revenue", "sCHG", "https://servoprotocol.xyz/rwa/charger")
        );
        share.mintShares(operator, 70e18);
        share.mintShares(BACKER, 30e18);

        // Route the charging service's revenue (SVC #1) straight into the share.
        SERVICES.updateService(1, address(share), 0.05e6, true, "https://servoprotocol.xyz/svc/1");
        vm.stopBroadcast();

        console.log("Charger RevenueShare:", address(share));
        console.log("SVC #1 payTo now routes here. Charges auto-distribute to holders.");
    }
}
