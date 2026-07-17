// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @dev Chainlink AggregatorV3Interface (the standard price-feed interface).
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title ServoOracle
/// @notice Values Servo's USDG-denominated figures in real USD using Chainlink's
///         live USDG/USD price feed on Robinhood Chain. Robinhood Chain is powered by
///         Chainlink, so revenue, share prices, and distributions can be shown in true
///         USD and reflect any USDG depeg, all verifiable onchain rather than assumed
///         to be exactly $1.
contract ServoOracle {
    /// @notice The Chainlink USDG/USD feed this oracle reads.
    AggregatorV3Interface public immutable USDG_USD;
    /// @notice Reject prices older than the feed heartbeat (86400s) plus a buffer.
    uint256 public constant MAX_STALENESS = 90_000;

    error StalePrice(uint256 updatedAt);
    error BadPrice(int256 answer);

    constructor(address usdgUsdFeed) {
        USDG_USD = AggregatorV3Interface(usdgUsdFeed);
    }

    /// @notice Latest USDG/USD price and the feed's decimals. Reverts if the price is
    ///         non-positive or stale.
    function usdgPrice() public view returns (int256 price, uint8 decimals) {
        (, int256 answer,, uint256 updatedAt,) = USDG_USD.latestRoundData();
        if (answer <= 0) revert BadPrice(answer);
        if (block.timestamp - updatedAt > MAX_STALENESS) revert StalePrice(updatedAt);
        return (answer, USDG_USD.decimals());
    }

    /// @notice Convert a USDG amount (6 decimals) to its USD value (18 decimals),
    ///         priced by Chainlink.
    function usdgToUsd(uint256 usdgAmount) external view returns (uint256) {
        (int256 price, uint8 dec) = usdgPrice();
        // usdgAmount(1e6) * price(1e{dec}) scaled to 1e18 USD:
        //   1e18 / (1e6 * 10^dec) = 1e12 / 10^dec
        return (usdgAmount * uint256(price) * 1e12) / (10 ** dec);
    }

    /// @notice Feed metadata passthrough.
    function feedDescription() external view returns (string memory) {
        return USDG_USD.description();
    }
}
