// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MachineRegistry} from "../src/MachineRegistry.sol";
import {ServiceRegistry} from "../src/ServiceRegistry.sol";
import {StockRewards} from "../src/StockRewards.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {MockSwapAdapter} from "./mocks/MockSwapAdapter.sol";

/// @notice Tests for marketplace stock rewards: a slice of the protocol fee on each
///         trade is credited to the buyer and claimed as tokenized stock.
contract StockRewardsTest is Test {
    MachineRegistry registry;
    ServiceRegistry services;
    StockRewards rewards;
    MockUSDC usdg;
    MockToken stock;
    MockSwapAdapter adapter;

    address gov = makeAddr("gov");
    address treasury = makeAddr("treasury");
    address provider = makeAddr("provider");
    address buyer = makeAddr("buyer");

    uint96 constant PRICE = 100e6; // 100 USDG
    uint16 constant REWARD_SHARE = 5000; // half the fee becomes a stock reward
    bytes32 constant CATEGORY = keccak256("CHARGING");

    // adapter rate: stockOut = usdgIn * 1e10  (100 USDG [100e6] -> 1 stock [1e18])
    uint256 constant RATE_NUM = 1e10;
    uint256 constant RATE_DEN = 1;

    uint256 serviceId;

    function setUp() public {
        registry = new MachineRegistry(gov);
        services = new ServiceRegistry(registry, gov, treasury);
        usdg = new MockUSDC();
        stock = new MockToken("Nvidia Stock Token", "NVDAx", 18);
        adapter = new MockSwapAdapter(stock, RATE_NUM, RATE_DEN);
        rewards = new StockRewards(usdg, gov);

        // Wire rewards: the registry is the recorder; a stock token is claimable.
        vm.startPrank(gov);
        rewards.setRecorder(address(services), true);
        rewards.setSwapAdapter(address(adapter));
        rewards.setAllowedStock(address(stock), true);
        rewards.setDefaultStock(address(stock));
        services.setStockRewards(address(rewards), REWARD_SHARE);
        vm.stopPrank();

        // A plain (non-machine) service priced in USDG.
        vm.prank(provider);
        serviceId = services.registerService(0, provider, address(usdg), PRICE, CATEGORY, false, "https://x402");

        usdg.mint(buyer, 1_000e6);
        vm.prank(buyer);
        usdg.approve(address(services), type(uint256).max);
    }

    function _buy() internal {
        vm.prank(buyer);
        services.purchase(serviceId, 0);
    }

    // ------------------------------------------------------------- accrual

    function test_purchase_splitsFeeAndCreditsBuyer() public {
        _buy();

        uint256 fee = (uint256(PRICE) * 100) / 10_000; // 1% = 1 USDG
        uint256 reward = (fee * REWARD_SHARE) / 10_000; // half = 0.5 USDG
        uint256 net = PRICE - fee;

        assertEq(usdg.balanceOf(buyer), 1_000e6 - PRICE, "buyer outlay is exactly price");
        assertEq(usdg.balanceOf(provider), net, "provider gets net");
        assertEq(usdg.balanceOf(treasury), fee - reward, "treasury gets fee minus reward");
        assertEq(usdg.balanceOf(address(rewards)), reward, "reward funds land in the pool");

        assertEq(rewards.accrued(buyer), reward, "buyer credited");
        assertEq(rewards.totalOwed(), reward);
        assertEq(rewards.totalEarned(), reward);
        assertEq(rewards.reserves(), rewards.totalOwed(), "pool solvent");
    }

    function test_claimAsStock_swapsUsdgReward() public {
        _buy();
        uint256 reward = rewards.accrued(buyer);

        vm.prank(buyer);
        uint256 out = rewards.claimAsStock(address(stock), 0);

        assertEq(out, reward * RATE_NUM / RATE_DEN, "stock out matches rate");
        assertEq(stock.balanceOf(buyer), out, "buyer holds the stock");
        assertEq(rewards.accrued(buyer), 0, "reward consumed");
        assertEq(rewards.totalOwed(), 0);
        assertEq(rewards.totalClaimed(), reward);
        assertEq(rewards.reserves(), 0, "usdg swapped out");
    }

    function test_claimDefault_usesDefaultStock() public {
        _buy();
        uint256 reward = rewards.accrued(buyer);
        vm.prank(buyer);
        uint256 out = rewards.claimDefault(0);
        assertEq(stock.balanceOf(buyer), out);
        assertEq(out, reward * RATE_NUM / RATE_DEN);
    }

    function test_claimAsUsdg_fallback() public {
        _buy();
        uint256 reward = rewards.accrued(buyer);
        vm.prank(buyer);
        uint256 got = rewards.claimAsUsdg();
        assertEq(got, reward);
        assertEq(usdg.balanceOf(buyer), 1_000e6 - PRICE + reward);
        assertEq(rewards.accrued(buyer), 0);
        assertEq(rewards.totalClaimed(), reward);
    }

    // --------------------------------------------------------- solvency

    function test_solvency_acrossManyBuyers() public {
        uint256 fee = (uint256(PRICE) * 100) / 10_000;
        uint256 reward = (fee * REWARD_SHARE) / 10_000;

        for (uint256 i = 0; i < 5; i++) {
            address b = makeAddr(string(abi.encodePacked("b", i)));
            usdg.mint(b, PRICE);
            vm.startPrank(b);
            usdg.approve(address(services), type(uint256).max);
            services.purchase(serviceId, 0);
            vm.stopPrank();
            assertEq(rewards.accrued(b), reward);
        }
        assertEq(rewards.totalOwed(), reward * 5);
        assertEq(rewards.reserves(), rewards.totalOwed(), "reserves always cover liabilities");
    }

    // --------------------------------------------------- disabled / guards

    function test_disabled_allFeeToTreasury() public {
        vm.prank(gov);
        services.setStockRewards(address(0), 0);

        _buy();
        uint256 fee = (uint256(PRICE) * 100) / 10_000;
        assertEq(usdg.balanceOf(treasury), fee, "full fee to treasury");
        assertEq(rewards.accrued(buyer), 0, "no reward accrued");
        assertEq(usdg.balanceOf(address(rewards)), 0);
    }

    function test_nonRewardCurrencyService_noReward() public {
        MockToken other = new MockToken("Other", "OTH", 6);
        vm.prank(provider);
        uint256 sid2 = services.registerService(0, provider, address(other), PRICE, CATEGORY, false, "u");

        other.mint(buyer, PRICE);
        vm.startPrank(buyer);
        other.approve(address(services), type(uint256).max);
        services.purchase(sid2, 0);
        vm.stopPrank();

        uint256 fee = (uint256(PRICE) * 100) / 10_000;
        assertEq(other.balanceOf(treasury), fee, "full fee to treasury in the service token");
        assertEq(rewards.accrued(buyer), 0, "no reward for non-USDG service");
    }

    // --------------------------------------------------- access control

    function test_accrue_onlyRecorder() public {
        vm.expectRevert(abi.encodeWithSelector(StockRewards.NotRecorder.selector, address(this)));
        rewards.accrue(buyer, 1e6);
    }

    function test_setStockRewards_onlyOwner() public {
        vm.expectRevert();
        services.setStockRewards(address(rewards), 1000);
    }

    function test_setStockRewards_rejectsTooHighShare() public {
        vm.prank(gov);
        vm.expectRevert(abi.encodeWithSelector(ServiceRegistry.RewardShareTooHigh.selector, uint16(10_001)));
        services.setStockRewards(address(rewards), 10_001);
    }

    // ----------------------------------------------------- claim guards

    function test_claim_nothingToClaim() public {
        vm.prank(buyer);
        vm.expectRevert(StockRewards.NothingToClaim.selector);
        rewards.claimAsUsdg();
    }

    function test_claim_stockNotAllowed() public {
        _buy();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(StockRewards.StockNotAllowed.selector, address(0xBEEF)));
        rewards.claimAsStock(address(0xBEEF), 0);
    }

    function test_claim_noSwapAdapter() public {
        vm.prank(gov);
        rewards.setSwapAdapter(address(0));
        _buy();
        vm.prank(buyer);
        vm.expectRevert(StockRewards.NoSwapAdapter.selector);
        rewards.claimAsStock(address(stock), 0);
    }

    function test_claim_respectsSlippage() public {
        _buy();
        uint256 reward = rewards.accrued(buyer);
        uint256 tooMuch = reward * RATE_NUM / RATE_DEN + 1;
        vm.prank(buyer);
        vm.expectRevert(MockSwapAdapter.Slippage.selector);
        rewards.claimAsStock(address(stock), tooMuch);
    }

    // ----------------------------------------------------------- rescue

    function test_rescue_cannotSweepOwedRewards() public {
        _buy();
        uint256 owed = rewards.totalOwed();
        vm.prank(gov);
        vm.expectRevert(StockRewards.AmountExceedsFree.selector);
        rewards.rescue(address(usdg), gov, owed);
    }

    function test_rescue_onlyExcess() public {
        _buy();
        usdg.mint(address(rewards), 10e6); // stray funds
        vm.prank(gov);
        rewards.rescue(address(usdg), gov, 10e6); // exactly the excess
        assertEq(usdg.balanceOf(gov), 10e6);
        assertEq(rewards.reserves(), rewards.totalOwed(), "owed still fully backed");
    }
}
