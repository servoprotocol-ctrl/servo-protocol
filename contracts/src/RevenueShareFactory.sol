// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShare} from "./RevenueShare.sol";

/// @title RevenueShareFactory
/// @notice Deploys and indexes RevenueShare tokens, one per real-world asset, so any
///         operator can put an income-producing asset on Servo's RWA Revenue Rails.
contract RevenueShareFactory {
    /// @notice Default settlement currency for revenue (USDG on Robinhood Chain).
    IERC20 public immutable ASSET;

    address[] public allShares;
    mapping(address share => address operator) public operatorOf;

    event RevenueShareCreated(
        address indexed share, address indexed operator, string name, string symbol
    );

    constructor(IERC20 asset) {
        ASSET = asset;
    }

    /// @notice Create a revenue-share token for a real-world asset. The caller becomes
    ///         the operator (owner) that issues shares and manages the asset.
    function createRevenueShare(
        string calldata name,
        string calldata symbol,
        string calldata assetURI
    ) external returns (address share) {
        RevenueShare rs = new RevenueShare(name, symbol, ASSET, msg.sender, assetURI);
        share = address(rs);
        allShares.push(share);
        operatorOf[share] = msg.sender;
        emit RevenueShareCreated(share, msg.sender, name, symbol);
    }

    function count() external view returns (uint256) {
        return allShares.length;
    }

    function shares() external view returns (address[] memory) {
        return allShares;
    }
}
