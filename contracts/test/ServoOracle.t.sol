// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ServoOracle} from "../src/ServoOracle.sol";

/// @dev Minimal mock of a Chainlink aggregator for testing.
contract MockAggregator {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public decimals = 8;
    string public description = "USDG / USD";

    constructor(int256 a, uint256 u) {
        answer = a;
        updatedAt = u;
    }

    function set(int256 a, uint256 u) external {
        answer = a;
        updatedAt = u;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract ServoOracleTest is Test {
    MockAggregator feed;
    ServoOracle oracle;

    function setUp() public {
        vm.warp(1_000_000);
        feed = new MockAggregator(99_995_000, block.timestamp); // $0.99995, fresh
        oracle = new ServoOracle(address(feed));
    }

    function test_usdgPrice() public view {
        (int256 price, uint8 dec) = oracle.usdgPrice();
        assertEq(price, 99_995_000);
        assertEq(dec, 8);
    }

    function test_usdgToUsd_atPeg() public {
        feed.set(1e8, block.timestamp); // exactly $1.00
        // 100 USDG (100e6) -> 100 USD (100e18)
        assertEq(oracle.usdgToUsd(100e6), 100e18);
    }

    function test_usdgToUsd_reflectsDepeg() public {
        feed.set(98e6, block.timestamp); // $0.98
        // 100 USDG -> 98 USD
        assertEq(oracle.usdgToUsd(100e6), 98e18);
    }

    function test_revertsOnStalePrice() public {
        feed.set(1e8, block.timestamp);
        vm.warp(block.timestamp + 90_001); // past MAX_STALENESS
        vm.expectRevert(abi.encodeWithSelector(ServoOracle.StalePrice.selector, feed.updatedAt()));
        oracle.usdgPrice();
    }

    function test_revertsOnBadPrice() public {
        feed.set(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ServoOracle.BadPrice.selector, int256(0)));
        oracle.usdgPrice();
    }
}
