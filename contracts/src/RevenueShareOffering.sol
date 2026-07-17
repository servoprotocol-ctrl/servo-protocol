// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title RevenueShareOffering
/// @notice Primary issuance for RWA Revenue Rails: an operator sells shares of a
///         real-world asset for USDG at a fixed price. Buyers pay USDG and receive
///         shares (a claim on the asset's future income); the proceeds go straight to
///         the operator. This is how a tokenized asset gets an initial price and how
///         the operator raises capital against it.
///
///         Flow: create -> operator fund()s the offering with share inventory ->
///         buyers buy() until sold out or the operator close()s and reclaims the rest.
///         Shares are 18-decimal; the offering trades in whole shares.
contract RevenueShareOffering is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant ONE_SHARE = 1e18;

    IERC20 public immutable SHARE; // the RevenueShare token being sold
    IERC20 public immutable PAY; // payment currency (USDG)
    address public immutable OPERATOR; // seller; receives proceeds and unsold inventory
    uint256 public immutable PRICE; // USDG base units per whole share

    uint256 public sharesSold; // whole shares sold
    uint256 public totalRaised; // USDG raised
    bool public closed;

    event Funded(uint256 wholeShares);
    event SharesPurchased(address indexed buyer, uint256 wholeShares, uint256 cost);
    event Closed(uint256 unsoldWholeShares);

    error NotOperator();
    error OfferingClosed();
    error ZeroAmount();
    error SoldOut(uint256 available);

    constructor(IERC20 share, IERC20 pay, address operator, uint256 price) {
        if (address(share) == address(0) || address(pay) == address(0) || operator == address(0)) {
            revert ZeroAmount();
        }
        if (price == 0) revert ZeroAmount();
        SHARE = share;
        PAY = pay;
        OPERATOR = operator;
        PRICE = price;
    }

    /// @notice Operator loads share inventory to sell. Requires prior approval of the
    ///         share token to this contract.
    function fund(uint256 wholeShares) external {
        if (msg.sender != OPERATOR) revert NotOperator();
        if (closed) revert OfferingClosed();
        if (wholeShares == 0) revert ZeroAmount();
        SHARE.safeTransferFrom(OPERATOR, address(this), wholeShares * ONE_SHARE);
        emit Funded(wholeShares);
    }

    /// @notice Buy `wholeShares` at the fixed price. Pays USDG to the operator and
    ///         receives the shares (and with them, a pro-rata claim on the asset's
    ///         future income).
    function buy(uint256 wholeShares) external nonReentrant {
        if (closed) revert OfferingClosed();
        if (wholeShares == 0) revert ZeroAmount();
        uint256 avail = available();
        if (wholeShares > avail) revert SoldOut(avail);

        uint256 cost = wholeShares * PRICE;
        PAY.safeTransferFrom(msg.sender, OPERATOR, cost); // proceeds straight to the operator
        SHARE.safeTransfer(msg.sender, wholeShares * ONE_SHARE);

        sharesSold += wholeShares;
        totalRaised += cost;
        emit SharesPurchased(msg.sender, wholeShares, cost);
    }

    /// @notice Operator ends the sale and reclaims any unsold shares.
    function close() external {
        if (msg.sender != OPERATOR) revert NotOperator();
        if (closed) revert OfferingClosed();
        closed = true;
        uint256 left = SHARE.balanceOf(address(this));
        if (left > 0) SHARE.safeTransfer(OPERATOR, left);
        emit Closed(left / ONE_SHARE);
    }

    // ----------------------------------------------------------------- views

    /// @notice Whole shares still available to buy.
    function available() public view returns (uint256) {
        return SHARE.balanceOf(address(this)) / ONE_SHARE;
    }

    /// @notice Cost in USDG to buy `wholeShares`.
    function quote(uint256 wholeShares) external view returns (uint256) {
        return wholeShares * PRICE;
    }
}
