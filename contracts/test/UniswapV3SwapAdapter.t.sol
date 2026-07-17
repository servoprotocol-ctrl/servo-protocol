// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {UniswapV3SwapAdapter, IV3SwapRouter} from "../src/UniswapV3SwapAdapter.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockV3Router} from "./mocks/MockV3Router.sol";

/// @notice Tests the production Uniswap v3 adapter against a mock router, and confirms it
///         satisfies the ISwapAdapter contract that StockRewards depends on.
contract UniswapV3SwapAdapterTest is Test {
    MockUSDC usdg;
    MockToken stock; // tokenized NVDA stand-in
    MockV3Router router;
    UniswapV3SwapAdapter adapter;

    address gov = makeAddr("gov");
    address user = makeAddr("user");

    uint24 constant FEE = 3000;
    uint256 constant RATE_NUM = 1e10; // 100 USDG [100e6] -> 1 stock [1e18]
    uint256 constant RATE_DEN = 1;

    function setUp() public {
        usdg = new MockUSDC();
        stock = new MockToken("Nvidia Stock Token", "NVDAx", 18);
        router = new MockV3Router(RATE_NUM, RATE_DEN);
        adapter = new UniswapV3SwapAdapter(IV3SwapRouter(address(router)), gov);

        vm.prank(gov);
        adapter.setPath(address(stock), abi.encodePacked(address(usdg), FEE, address(stock)));
    }

    function test_swap_viaConfiguredPath() public {
        usdg.mint(address(this), 100e6);
        usdg.approve(address(adapter), 100e6);

        uint256 out = adapter.swap(address(usdg), address(stock), 100e6, 0, user);

        assertEq(out, 100e6 * RATE_NUM / RATE_DEN, "output matches rate");
        assertEq(stock.balanceOf(user), out, "stock delivered to recipient");
        assertEq(usdg.balanceOf(address(adapter)), 0, "no usdg stuck in adapter");
        assertEq(usdg.allowance(address(adapter), address(router)), 0, "router approval reset");
    }

    function test_swap_noPath_reverts() public {
        MockToken other = new MockToken("Other", "OTH", 18);
        usdg.mint(address(this), 10e6);
        usdg.approve(address(adapter), 10e6);
        vm.expectRevert(abi.encodeWithSelector(UniswapV3SwapAdapter.NoPath.selector, address(other)));
        adapter.swap(address(usdg), address(other), 10e6, 0, user);
    }

    function test_swap_respectsMinOut() public {
        usdg.mint(address(this), 100e6);
        usdg.approve(address(adapter), 100e6);
        uint256 tooMuch = 100e6 * RATE_NUM / RATE_DEN + 1;
        vm.expectRevert(MockV3Router.Slippage.selector);
        adapter.swap(address(usdg), address(stock), 100e6, tooMuch, user);
    }

    function test_setPath_onlyOwner() public {
        vm.expectRevert();
        adapter.setPath(address(stock), abi.encodePacked(address(usdg), FEE, address(stock)));
    }

    /// @notice End-to-end: StockRewards uses the real adapter shape to pay a stock reward.
    function test_integration_stockRewardsClaimsThroughAdapter() public {
        StockRewards rewards = new StockRewards(usdg, gov);
        vm.startPrank(gov);
        rewards.setRecorder(gov, true);
        rewards.setSwapAdapter(address(adapter));
        rewards.setAllowedStock(address(stock), true);
        vm.stopPrank();

        // Fund the pool and credit the user (mimicking a fee diversion + accrue).
        usdg.mint(gov, 50e6);
        vm.startPrank(gov);
        usdg.approve(address(rewards), 50e6);
        rewards.fund(50e6);
        rewards.accrue(user, 50e6);
        vm.stopPrank();

        vm.prank(user);
        uint256 out = rewards.claimAsStock(address(stock), 0);

        assertEq(out, 50e6 * RATE_NUM / RATE_DEN);
        assertEq(stock.balanceOf(user), out);
        assertEq(rewards.accrued(user), 0);
        assertEq(rewards.reserves(), 0, "usdg swapped out of the pool");
    }
}
