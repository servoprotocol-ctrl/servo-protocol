// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShareOfferingFactory} from "../src/RevenueShareOfferingFactory.sol";
import {RevenueShareOffering} from "../src/RevenueShareOffering.sol";

contract DemoOffering is Script {
    RevenueShareOfferingFactory constant F = RevenueShareOfferingFactory(0x371877b3310aEd85a6c85d0f846F13Fb9bcC9Df7);
    IERC20 constant CHARGER_SHARE = IERC20(0x664b19AC98fEb5051d4aE659eBb4D8B6e326CD0e);
    function run() external {
        vm.startBroadcast();
        address offering = F.createOffering(CHARGER_SHARE, 0.5e6); // 0.5 USDG per share
        CHARGER_SHARE.approve(offering, 20e18);
        RevenueShareOffering(offering).fund(20); // list 20 shares for sale
        vm.stopBroadcast();
        console.log("Offering:", offering);
        console.log("Selling 20 charger shares at 0.5 USDG each.");
    }
}
