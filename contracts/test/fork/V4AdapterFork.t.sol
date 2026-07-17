// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniswapV4SwapAdapter} from "../../src/UniswapV4SwapAdapter.sol";
import {IPoolManagerMinimal, PoolKey} from "../../src/interfaces/IPoolManagerMinimal.sol";
import {StockRewards} from "../../src/StockRewards.sol";

/// @notice Fork tests against the REAL Robinhood Chain: swaps USDG into the real
///         tokenized NVDA through the real v4 PoolManager pool. Run explicitly with:
///
///           forge test --match-contract V4AdapterFork \
///             --fork-url https://rpc.mainnet.chain.robinhood.com -vv
///
///         Skipped automatically when not forking (chainid gate), so the normal suite
///         stays offline and fast.
contract V4AdapterForkTest is Test {
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant NVDA = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;

    function _pool() internal pure returns (PoolKey memory) {
        (address c0, address c1) = USDG < NVDA ? (USDG, NVDA) : (NVDA, USDG);
        return PoolKey({currency0: c0, currency1: c1, fee: 3000, tickSpacing: 60, hooks: address(0)});
    }

    modifier onlyFork() {
        if (block.chainid != 4663) {
            emit log("skipped: not forking Robinhood Chain (4663)");
            return;
        }
        _;
    }

    function test_fork_swapUsdgToRealNvda() public onlyFork {
        UniswapV4SwapAdapter adapter =
            new UniswapV4SwapAdapter(IPoolManagerMinimal(POOL_MANAGER), address(this));
        adapter.setPool(NVDA, _pool());

        address user = makeAddr("user");
        deal(USDG, address(this), 100e6);
        IERC20(USDG).approve(address(adapter), 100e6);

        uint256 out = adapter.swap(USDG, NVDA, 100e6, 0, user);

        emit log_named_uint("NVDA out for 100 USDG (1e18)", out);
        assertGt(out, 0.3e18, "at ~$200/share, 100 USDG should buy > 0.3 NVDA");
        assertLt(out, 1e18, "and well under 1 NVDA");
        assertEq(IERC20(NVDA).balanceOf(user), out, "real NVDA delivered to recipient");
        assertEq(IERC20(USDG).balanceOf(address(adapter)), 0, "no USDG stranded");
    }

    function test_fork_fullRewardLoop_accrueToNvdaClaim() public onlyFork {
        UniswapV4SwapAdapter adapter =
            new UniswapV4SwapAdapter(IPoolManagerMinimal(POOL_MANAGER), address(this));
        adapter.setPool(NVDA, _pool());

        StockRewards rewards = new StockRewards(IERC20(USDG), address(this));
        rewards.setRecorder(address(this), true);
        rewards.setSwapAdapter(address(adapter));
        rewards.setAllowedStock(NVDA, true);
        rewards.setDefaultStock(NVDA);

        // Fund the pool and credit a user, mimicking marketplace fee diversion.
        address user = makeAddr("user");
        deal(USDG, address(this), 25e6);
        IERC20(USDG).approve(address(rewards), 25e6);
        rewards.fund(25e6);
        rewards.accrue(user, 25e6);

        vm.prank(user);
        uint256 out = rewards.claimDefault(0);

        emit log_named_uint("real NVDA claimed for 25 USDG of rewards (1e18)", out);
        assertGt(out, 0, "claim paid out real NVDA");
        assertEq(IERC20(NVDA).balanceOf(user), out);
        assertEq(rewards.accrued(user), 0);
    }
}
