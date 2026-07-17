// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {RevenueShare} from "../src/RevenueShare.sol";
import {RevenueShareFactory} from "../src/RevenueShareFactory.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests for RWA Revenue Rails: revenue paid into a RevenueShare is
///         distributed to holders pro-rata, survives share transfers, and can be
///         claimed exactly once. USDG is mocked at 6 decimals.
///
///         Distribution rounds DOWN (conservative): a holder can be short by up to a
///         base unit of dust (1e-6 USDG), which stays in the contract and is never
///         over-distributed. Assertions use a small tolerance to reflect that.
contract RevenueShareTest is Test {
    RevenueShareFactory factory;
    RevenueShare share;
    MockUSDC usdg;

    uint256 constant DUST = 5; // base units (5e-6 USDG) tolerance for rounding dust

    address operator = makeAddr("operator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address payer = makeAddr("payer");

    function setUp() public {
        usdg = new MockUSDC();
        factory = new RevenueShareFactory(IERC20(address(usdg)));

        vm.prank(operator);
        share = RevenueShare(factory.createRevenueShare("Charger 001 Shares", "CHG1", "ipfs://asset"));

        vm.startPrank(operator);
        share.mintShares(alice, 60e18); // 60%
        share.mintShares(bob, 40e18); // 40%
        vm.stopPrank();

        usdg.mint(payer, 10_000e6);
        vm.prank(payer);
        usdg.approve(address(share), type(uint256).max);
    }

    function _deposit(uint256 amount) internal {
        vm.prank(payer);
        share.depositRevenue(amount);
    }

    // ---------------------------------------------------------------- core

    function test_proRataDistribution() public {
        _deposit(100e6);
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 40e6, DUST);
        assertEq(share.totalRevenueDistributed(), 100e6);
    }

    function test_claim() public {
        _deposit(100e6);

        vm.prank(alice);
        share.claim();
        assertApproxEqAbs(usdg.balanceOf(alice), 60e6, DUST);
        assertEq(share.withdrawableRevenueOf(alice), 0);

        vm.prank(alice);
        vm.expectRevert(RevenueShare.NothingToClaim.selector);
        share.claim();

        vm.prank(bob);
        share.claim();
        assertApproxEqAbs(usdg.balanceOf(bob), 40e6, DUST);
    }

    function test_multipleDeposits_accumulate() public {
        _deposit(100e6);
        _deposit(50e6);
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 90e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 60e6, DUST);
    }

    // -------------------------------------------------- transfers carry entitlement

    function test_transferAfterDeposit_keepsPastRevenueWithSeller() public {
        _deposit(100e6);

        vm.prank(alice);
        share.transfer(carol, 60e18);

        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 60e6, DUST);
        assertEq(share.withdrawableRevenueOf(carol), 0);

        _deposit(100e6); // now carol 60%, bob 40%
        assertApproxEqAbs(share.withdrawableRevenueOf(carol), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 80e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 60e6, DUST); // unchanged
    }

    function test_transferBeforeDeposit_movesFutureRevenue() public {
        vm.prank(alice);
        share.transfer(carol, 60e18);

        _deposit(100e6);
        assertApproxEqAbs(share.withdrawableRevenueOf(carol), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 40e6, DUST);
        assertEq(share.withdrawableRevenueOf(alice), 0);
    }

    function test_newShares_notOwedPastRevenue() public {
        _deposit(100e6);

        vm.prank(operator);
        share.mintShares(carol, 100e18);
        assertEq(share.withdrawableRevenueOf(carol), 0);
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 60e6, DUST);

        _deposit(100e6); // 200 shares: alice 30%, bob 20%, carol 50%
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 90e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(carol), 50e6, DUST);
    }

    // ----------------------------------------------------------------- guards

    function test_depositWithNoShares_reverts() public {
        vm.prank(operator);
        RevenueShare empty = RevenueShare(factory.createRevenueShare("Empty", "EMP", ""));
        usdg.mint(payer, 10e6);
        vm.startPrank(payer);
        usdg.approve(address(empty), 10e6);
        vm.expectRevert(RevenueShare.NoShares.selector);
        empty.depositRevenue(10e6);
        vm.stopPrank();
    }

    function test_mintShares_onlyOperator() public {
        vm.prank(alice);
        vm.expectRevert();
        share.mintShares(alice, 1e18);
    }

    /// @notice The core safety invariant: total claimable never exceeds deposits.
    function test_neverOverDistributes() public {
        _deposit(100e6);
        _deposit(33e6); // odd amount

        uint256 a = share.withdrawableRevenueOf(alice);
        uint256 b = share.withdrawableRevenueOf(bob);
        assertLe(a + b, 133e6); // never more than paid in
        assertGe(a + b, 133e6 - DUST); // and only dust short

        vm.prank(alice);
        share.claim();
        vm.prank(bob);
        share.claim();
        assertEq(usdg.balanceOf(alice) + usdg.balanceOf(bob), a + b);
        // dust remains in the contract, unclaimed
        assertLe(usdg.balanceOf(address(share)), DUST);
    }

    function test_factory_indexesShares() public {
        assertEq(factory.count(), 1);
        assertEq(factory.operatorOf(address(share)), operator);
        assertEq(factory.allShares(0), address(share));
    }

    // ------------------------------------------------ auto-routing (income lands directly)

    /// @notice The killer feature: income sent straight to the contract (e.g. a machine's
    ///         marketplace revenue) is distributed to holders on sync, no deposit call.
    function test_autoRouting_directTransferThenSync() public {
        // simulate the asset earning: USDG lands directly in the contract
        vm.prank(payer);
        usdg.transfer(address(share), 100e6);

        // nothing distributed until synced
        assertEq(share.withdrawableRevenueOf(alice), 0);

        share.syncRevenue(); // permissionless
        assertApproxEqAbs(share.withdrawableRevenueOf(alice), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 40e6, DUST);
        assertEq(share.totalRevenueDistributed(), 100e6);
    }

    function test_autoRouting_claimAutoSyncs() public {
        // income lands directly; a holder claims without anyone calling sync first
        vm.prank(payer);
        usdg.transfer(address(share), 100e6);

        vm.prank(alice);
        share.claim(); // claim auto-syncs, so alice still gets her 60
        assertApproxEqAbs(usdg.balanceOf(alice), 60e6, DUST);
        assertApproxEqAbs(share.withdrawableRevenueOf(bob), 40e6, DUST);
    }

    function test_autoRouting_dustNotRedistributed() public {
        vm.prank(payer);
        usdg.transfer(address(share), 100e6);
        share.syncRevenue();

        vm.prank(alice);
        share.claim();
        vm.prank(bob);
        share.claim();

        // syncing again must not invent revenue from leftover dust
        uint256 distributedBefore = share.totalRevenueDistributed();
        share.syncRevenue();
        assertEq(share.totalRevenueDistributed(), distributedBefore);
    }
}
