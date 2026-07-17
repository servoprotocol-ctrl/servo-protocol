// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShareOfferingFactory} from "../src/RevenueShareOfferingFactory.sol";

/// @notice Deploys the primary-issuance factory to Robinhood Chain.
contract DeployOffering is Script {
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    function run() external {
        vm.startBroadcast();
        RevenueShareOfferingFactory f = new RevenueShareOfferingFactory(IERC20(USDG));
        vm.stopBroadcast();
        console.log("RevenueShareOfferingFactory:", address(f));
    }
}
