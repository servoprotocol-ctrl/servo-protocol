// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RevenueShare} from "../src/RevenueShare.sol";
import {RevenueShareFactory} from "../src/RevenueShareFactory.sol";
import {RevenueShareOffering} from "../src/RevenueShareOffering.sol";
import {RevenueShareOfferingFactory} from "../src/RevenueShareOfferingFactory.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Primary issuance: an operator lists shares of an asset for USDG, buyers
///         purchase, shares transfer to buyers and proceeds go to the operator.
contract RevenueShareOfferingTest is Test {
    RevenueShareFactory shareFactory;
    RevenueShareOfferingFactory offeringFactory;
    RevenueShare share;
    RevenueShareOffering offering;
    MockUSDC usdg;

    address operator = makeAddr("operator");
    address alice = makeAddr("alice"); // buyer
    address bob = makeAddr("bob"); // buyer

    uint256 constant PRICE = 8e6; // 8 USDG per whole share

    function setUp() public {
        usdg = new MockUSDC();
        shareFactory = new RevenueShareFactory(IERC20(address(usdg)));
        offeringFactory = new RevenueShareOfferingFactory(IERC20(address(usdg)));

        vm.startPrank(operator);
        share = RevenueShare(shareFactory.createRevenueShare("Charger Shares", "sCHG", ""));
        share.mintShares(operator, 100e18); // operator owns all 100 shares
        offering = RevenueShareOffering(offeringFactory.createOffering(IERC20(address(share)), PRICE));
        // fund the offering with 40 shares to sell
        share.approve(address(offering), 40e18);
        offering.fund(40);
        vm.stopPrank();

        usdg.mint(alice, 1_000e6);
        usdg.mint(bob, 1_000e6);
        vm.prank(alice);
        usdg.approve(address(offering), type(uint256).max);
        vm.prank(bob);
        usdg.approve(address(offering), type(uint256).max);
    }

    function test_buy_transfersSharesAndPaysOperator() public {
        vm.prank(alice);
        offering.buy(10); // 10 shares * 8 USDG = 80 USDG

        assertEq(share.balanceOf(alice), 10e18);
        assertEq(usdg.balanceOf(alice), 1_000e6 - 80e6);
        assertEq(usdg.balanceOf(operator), 80e6); // proceeds to operator
        assertEq(offering.sharesSold(), 10);
        assertEq(offering.totalRaised(), 80e6);
        assertEq(offering.available(), 30); // 40 funded - 10 sold
    }

    function test_buyer_earnsFutureRevenue() public {
        // alice buys 10 of 100 shares = 10%
        vm.prank(alice);
        offering.buy(10);

        // the asset earns 100 USDG; alice should be owed 10%
        usdg.mint(address(this), 100e6);
        usdg.approve(address(share), 100e6);
        share.depositRevenue(100e6);

        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 10e6, 5);
    }

    function test_soldOut_reverts() public {
        vm.prank(alice);
        offering.buy(40); // buys the whole inventory
        assertEq(offering.available(), 0);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(RevenueShareOffering.SoldOut.selector, 0));
        offering.buy(1);
    }

    function test_quote() public view {
        assertEq(offering.quote(5), 40e6); // 5 * 8 USDG
    }

    function test_close_returnsUnsoldToOperator() public {
        vm.prank(alice);
        offering.buy(15);

        vm.prank(operator);
        offering.close();

        // operator gets the 25 unsold shares back
        assertEq(share.balanceOf(operator), 60e18 + 25e18); // kept 60, plus 25 returned
        assertTrue(offering.closed());

        vm.prank(bob);
        vm.expectRevert(RevenueShareOffering.OfferingClosed.selector);
        offering.buy(1);
    }

    function test_fund_onlyOperator() public {
        vm.prank(alice);
        vm.expectRevert(RevenueShareOffering.NotOperator.selector);
        offering.fund(1);
    }

    function test_factory_indexes() public view {
        assertEq(offeringFactory.count(), 1);
        assertEq(offeringFactory.shareOf(address(offering)), address(share));
        assertEq(offeringFactory.allOfferings(0), address(offering));
    }
}
