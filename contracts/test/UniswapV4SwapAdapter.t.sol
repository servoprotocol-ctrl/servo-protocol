// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {UniswapV4SwapAdapter} from "../src/UniswapV4SwapAdapter.sol";
import {IPoolManagerMinimal, PoolKey} from "../src/interfaces/IPoolManagerMinimal.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockPoolManagerV4} from "./mocks/MockPoolManagerV4.sol";

/// @notice Tests the v4 swap adapter (the production path for stock tokens on Robinhood
///         Chain, where stock liquidity lives in v4 pools) against a mock PoolManager
///         that reproduces the unlock/swap/settle/take flow.
contract UniswapV4SwapAdapterTest is Test {
    MockUSDC usdg;
    MockToken stock; // tokenized NVDA stand-in (currency1: mock addr sorts above usdg in setup)
    MockPoolManagerV4 pm;
    UniswapV4SwapAdapter adapter;

    address gov = makeAddr("gov");
    address user = makeAddr("user");

    uint256 constant RATE_NUM = 1e10; // 100 USDG [100e6] -> 1 stock [1e18]
    uint256 constant RATE_DEN = 1;

    PoolKey key;

    function setUp() public {
        usdg = new MockUSDC();
        stock = new MockToken("Nvidia Stock Token", "NVDAx", 18);
        pm = new MockPoolManagerV4(RATE_NUM, RATE_DEN);
        adapter = new UniswapV4SwapAdapter(IPoolManagerMinimal(address(pm)), gov);

        // Mirror the live USDG/NVDA pool shape: 0.30% fee, tickSpacing 60, no hooks.
        (address c0, address c1) =
            address(usdg) < address(stock) ? (address(usdg), address(stock)) : (address(stock), address(usdg));
        key = PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});

        vm.prank(gov);
        adapter.setPool(address(stock), key);
    }

    function test_swap_deliversStockToRecipient() public {
        usdg.mint(address(this), 100e6);
        usdg.approve(address(adapter), 100e6);

        uint256 out = adapter.swap(address(usdg), address(stock), 100e6, 0, user);

        assertEq(out, 100e6 * RATE_NUM / RATE_DEN, "output at pool rate");
        assertEq(stock.balanceOf(user), out, "stock taken straight to recipient");
        assertEq(usdg.balanceOf(address(adapter)), 0, "no usdg stranded in adapter");
        assertEq(usdg.balanceOf(address(pm)), 100e6, "pool received the input");
    }

    function test_swap_enforcesMinOut() public {
        usdg.mint(address(this), 100e6);
        usdg.approve(address(adapter), 100e6);
        uint256 expected = 100e6 * RATE_NUM / RATE_DEN;
        vm.expectRevert(
            abi.encodeWithSelector(UniswapV4SwapAdapter.InsufficientOutput.selector, expected, expected + 1)
        );
        adapter.swap(address(usdg), address(stock), 100e6, expected + 1, user);
    }

    function test_swap_noPool_reverts() public {
        MockToken other = new MockToken("Other", "OTH", 18);
        usdg.mint(address(this), 10e6);
        usdg.approve(address(adapter), 10e6);
        vm.expectRevert(abi.encodeWithSelector(UniswapV4SwapAdapter.NoPool.selector, address(other)));
        adapter.swap(address(usdg), address(other), 10e6, 0, user);
    }

    function test_swap_wrongTokenIn_reverts() public {
        MockToken other = new MockToken("Other", "OTH", 6);
        other.mint(address(this), 10e6);
        other.approve(address(adapter), 10e6);
        vm.expectRevert(
            abi.encodeWithSelector(UniswapV4SwapAdapter.TokenNotInPool.selector, address(other), address(stock))
        );
        adapter.swap(address(other), address(stock), 10e6, 0, user);
    }

    function test_unlockCallback_onlyPoolManager() public {
        vm.expectRevert(abi.encodeWithSelector(UniswapV4SwapAdapter.NotPoolManager.selector, address(this)));
        adapter.unlockCallback("");
    }

    function test_setPool_onlyOwner() public {
        vm.expectRevert();
        adapter.setPool(address(stock), key);
    }

    function test_setPool_mustContainToken() public {
        MockToken other = new MockToken("Other", "OTH", 18);
        vm.prank(gov);
        vm.expectRevert(
            abi.encodeWithSelector(UniswapV4SwapAdapter.TokenNotInPool.selector, address(0), address(other))
        );
        adapter.setPool(address(other), key);
    }

    /// @notice End-to-end: a StockRewards claim pays out stock through the v4 adapter.
    function test_integration_stockRewardsClaimThroughV4() public {
        StockRewards rewards = new StockRewards(usdg, gov);
        vm.startPrank(gov);
        rewards.setRecorder(gov, true);
        rewards.setSwapAdapter(address(adapter));
        rewards.setAllowedStock(address(stock), true);
        rewards.setDefaultStock(address(stock));
        vm.stopPrank();

        usdg.mint(gov, 50e6);
        vm.startPrank(gov);
        usdg.approve(address(rewards), 50e6);
        rewards.fund(50e6);
        rewards.accrue(user, 50e6);
        vm.stopPrank();

        vm.prank(user);
        uint256 out = rewards.claimDefault(0);

        assertEq(out, 50e6 * RATE_NUM / RATE_DEN);
        assertEq(stock.balanceOf(user), out, "user paid in stock via v4");
        assertEq(rewards.accrued(user), 0);
        assertEq(rewards.reserves(), 0);
    }
}
