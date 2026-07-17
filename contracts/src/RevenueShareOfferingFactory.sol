// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RevenueShareOffering} from "./RevenueShareOffering.sol";

/// @title RevenueShareOfferingFactory
/// @notice Deploys and indexes primary offerings, so operators can list an asset's
///         shares for sale and investors can browse open offerings in one place.
contract RevenueShareOfferingFactory {
    /// @notice Payment currency for all offerings (USDG on Robinhood Chain).
    IERC20 public immutable PAY;

    address[] public allOfferings;
    mapping(address offering => address share) public shareOf;

    event OfferingCreated(
        address indexed offering, address indexed share, address indexed operator, uint256 price
    );

    constructor(IERC20 pay) {
        PAY = pay;
    }

    /// @notice Create a fixed-price offering for a RevenueShare. Caller is the operator
    ///         (seller). After creating, fund it by approving the share token to the
    ///         offering and calling offering.fund(wholeShares).
    /// @param share  the RevenueShare token to sell
    /// @param price  USDG base units per whole share
    function createOffering(IERC20 share, uint256 price) external returns (address offering) {
        RevenueShareOffering o = new RevenueShareOffering(share, PAY, msg.sender, price);
        offering = address(o);
        allOfferings.push(offering);
        shareOf[offering] = address(share);
        emit OfferingCreated(offering, address(share), msg.sender, price);
    }

    function count() external view returns (uint256) {
        return allOfferings.length;
    }

    function offerings() external view returns (address[] memory) {
        return allOfferings;
    }
}
