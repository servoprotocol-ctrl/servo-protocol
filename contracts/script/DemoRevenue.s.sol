// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShareFactory} from "../src/RevenueShareFactory.sol";
import {RevenueShare} from "../src/RevenueShare.sol";

/// @notice Genesis RWA Revenue Rails demo on Robinhood Chain: tokenize the charging
///         station's income, split ownership 70/30, pay 1 USDG of revenue in, and
///         watch it distribute to holders. Operator claims its share live.
contract DemoRevenue is Script {
    RevenueShareFactory constant FACTORY = RevenueShareFactory(0xa1e5fd12719Ae6a98c1b35bbE75bb71e4543529f);
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant BACKER = 0x05Bd1b6E853e5cEd23F79167C0023e4294689FA4;

    function run() external {
        address operator = msg.sender;

        vm.startBroadcast();
        // Tokenize the charging station's revenue.
        RevenueShare share = RevenueShare(
            FACTORY.createRevenueShare("Servo Genesis Charger", "sCHG1", "https://servoprotocol.xyz/rwa/1")
        );

        // Split ownership: operator 70%, a backer 30%.
        share.mintShares(operator, 70e18);
        share.mintShares(BACKER, 30e18);

        // Pay 1 USDG of real-world income into the asset.
        IERC20(USDG).approve(address(share), 1e6);
        share.depositRevenue(1e6);

        // Operator claims its 0.70 USDG share of the income.
        share.claim();
        vm.stopBroadcast();

        console.log("RevenueShare (charger):", address(share));
        console.log("operator claimable now:", share.withdrawableRevenueOf(operator));
        console.log("backer  claimable now: ", share.withdrawableRevenueOf(BACKER));
        console.log("total revenue in:      ", share.totalRevenueDistributed());
    }
}
