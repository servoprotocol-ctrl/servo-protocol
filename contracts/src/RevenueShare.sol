// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title RevenueShare
/// @notice The core of Servo's RWA Revenue Rails: real-world income routed onchain
///         and paid to the people who own the asset.
///
///         Each RevenueShare token is fractional ownership of a real-world asset (a
///         robot, a fleet, a charging station, any income-producing machine). USDG
///         revenue paid into the contract is distributed to holders pro-rata to their
///         holdings, using an O(1) accumulator so it scales to any number of holders
///         with no loops. Holders claim their accrued income at any time, and share
///         transfers carry the correct entitlement automatically.
///
///         Deposits are permissionless: an operator, a FleetVault, the asset's own
///         MachineAccount, or any payer can pay income in. The lifetime total is a
///         provable, onchain P&L for the asset.
contract RevenueShare is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Revenue settlement currency (canonically USDG on Robinhood Chain).
    IERC20 public immutable ASSET;

    /// @dev Fixed-point scale for per-share accounting. 2**160 makes distribution
    ///      exact at USDG's 6-decimal resolution against 18-decimal shares, while
    ///      `magnifiedRevenuePerShare * balance` stays far below int256 max for any
    ///      realistic revenue (headroom of ~10^10x even at trillions of USDG).
    uint256 internal constant MAGNITUDE = 2 ** 160;

    uint256 internal magnifiedRevenuePerShare;
    mapping(address holder => int256) internal magnifiedCorrections;
    mapping(address holder => uint256) public withdrawnRevenue;

    /// @notice Lifetime revenue routed through distribution. The asset's onchain P&L.
    uint256 public totalRevenueDistributed;
    /// @notice Lifetime revenue claimed by holders.
    uint256 public totalWithdrawn;
    /// @notice Metadata pointer for the underlying real-world asset.
    string public assetURI;

    event RevenueDistributed(uint256 amount, uint256 perShareAdded);
    event RevenueClaimed(address indexed holder, uint256 amount);
    event SharesMinted(address indexed to, uint256 amount);
    event AssetURIUpdated(string uri);

    error NoShares();
    error ZeroAmount();
    error NothingToClaim();
    error ZeroAddress();

    constructor(
        string memory name_,
        string memory symbol_,
        IERC20 asset_,
        address operator_,
        string memory assetURI_
    ) ERC20(name_, symbol_) Ownable(operator_) {
        if (address(asset_) == address(0)) revert ZeroAddress();
        ASSET = asset_;
        assetURI = assetURI_;
    }

    // ---------------------------------------------------------------- ownership shares

    /// @notice Operator issues ownership shares of the asset to holders.
    function mintShares(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
        emit SharesMinted(to, amount);
    }

    function setAssetURI(string calldata uri) external onlyOwner {
        assetURI = uri;
        emit AssetURIUpdated(uri);
    }

    // ------------------------------------------------------------------------- revenue

    /// @notice Pay revenue into the asset (explicit push). Distributed pro-rata.
    function depositRevenue(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (totalSupply() == 0) revert NoShares();
        ASSET.safeTransferFrom(msg.sender, address(this), amount);
        _sync();
    }

    /// @notice Distribute any income that has landed in this contract but not yet been
    ///         accounted, then... this is the auto-routing hook. A machine's marketplace
    ///         revenue can pay directly into this contract; a single permissionless
    ///         sync (or any holder's claim) distributes it to shareholders. No manual
    ///         deposit needed: the asset earns, and its owners get paid.
    function syncRevenue() external nonReentrant {
        _sync();
    }

    /// @notice Claim your accrued revenue. Auto-syncs first so any freshly-routed
    ///         income is included.
    function claim() external nonReentrant {
        _sync();
        uint256 claimable = withdrawableRevenueOf(msg.sender);
        if (claimable == 0) revert NothingToClaim();
        withdrawnRevenue[msg.sender] += claimable;
        totalWithdrawn += claimable;
        ASSET.safeTransfer(msg.sender, claimable);
        emit RevenueClaimed(msg.sender, claimable);
    }

    /// @dev Distribute the untracked balance: everything the contract holds beyond what
    ///      is already owed to holders. Dust from prior rounding is never re-distributed.
    function _sync() internal {
        uint256 supply = totalSupply();
        if (supply == 0) return;
        uint256 tracked = totalRevenueDistributed - totalWithdrawn; // owed + accumulated dust
        uint256 bal = ASSET.balanceOf(address(this));
        if (bal <= tracked) return;
        uint256 pending = bal - tracked;
        uint256 perShareAdded = (pending * MAGNITUDE) / supply;
        magnifiedRevenuePerShare += perShareAdded;
        totalRevenueDistributed += pending;
        emit RevenueDistributed(pending, perShareAdded);
    }

    // ----------------------------------------------------------------------------- views

    /// @notice Total revenue a holder has ever been entitled to (claimed + claimable).
    function accumulativeRevenueOf(address holder) public view returns (uint256) {
        int256 acc = (magnifiedRevenuePerShare * balanceOf(holder)).toInt256() + magnifiedCorrections[holder];
        // acc is non-negative by construction of the correction accounting.
        return uint256(acc) / MAGNITUDE;
    }

    /// @notice Revenue a holder can claim right now.
    function withdrawableRevenueOf(address holder) public view returns (uint256) {
        return accumulativeRevenueOf(holder) - withdrawnRevenue[holder];
    }

    // -------------------------------------------------------------- dividend accounting

    /// @dev Keeps each holder's entitlement correct across mint, burn, and transfer.
    ///      A share carries the revenue-per-share accrued *before* it was received, so
    ///      corrections offset the flat `magnifiedRevenuePerShare * balance` term.
    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        int256 magCorrection = (magnifiedRevenuePerShare * value).toInt256();
        if (from == address(0)) {
            // mint: new shares are not owed past revenue
            magnifiedCorrections[to] -= magCorrection;
        } else if (to == address(0)) {
            // burn
            magnifiedCorrections[from] += magCorrection;
        } else {
            // transfer: move the correction with the shares
            magnifiedCorrections[from] += magCorrection;
            magnifiedCorrections[to] -= magCorrection;
        }
    }
}
